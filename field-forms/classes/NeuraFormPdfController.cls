/**
 * Generates a branded PDF report for a completed Linked_Form and saves it
 * as a ContentVersion attached to that Linked_Form (and, when available,
 * to the parent WorkOrder/WOLI/ServiceAppointment so dispatchers can see
 * it without drilling into the form record).
 *
 * Renders via a Visualforce page (NeuraFormReportPDF) with renderAs="pdf".
 * The page reads its data from this controller via the standard Apex
 * controller pattern — getReportData() is called by the page lifecycle.
 */
public with sharing class NeuraFormPdfController {

    // ---- Visualforce-driven render path ------------------------------------

    public Id linkedFormId { get; set; }
    public ReportData data { get; set; }

    public NeuraFormPdfController() {
        String idParam = ApexPages.currentPage()?.getParameters()?.get('id');
        if (String.isNotBlank(idParam)) {
            this.linkedFormId = idParam;
            this.data = loadReportData(this.linkedFormId);
        }
    }

    // ---- LWC-driven generation path ----------------------------------------

    @AuraEnabled
    public static String generatePdfForLinkedForm(Id linkedFormId) {
        if (linkedFormId == null) {
            throw new AuraHandledException('linkedFormId is required.');
        }
        try {
            // Lookup name for the file. Best-effort; fall back to Id.
            List<Linked_Form__c> lfs = [
                SELECT Id, Name, Form_Template__r.Name, Work_Order__c,
                       Work_Order_Line_Item__c, Service_Appointment__c
                FROM Linked_Form__c
                WHERE Id = :linkedFormId
                LIMIT 1
            ];
            if (lfs.isEmpty()) {
                throw new AuraHandledException('Linked Form not found.');
            }
            Linked_Form__c lf = lfs[0];

            String tplName = lf.Form_Template__r != null
                ? lf.Form_Template__r.Name : 'Form';
            String title = tplName + ' - ' + lf.Name;
            String fileName = (title + '.pdf')
                .replaceAll('[\\\\/:*?"<>|]', '_');

            // Idempotency: completion can double-fire from the UI (double-tap,
            // duplicated submit event). If this form already got its PDF in
            // the last few minutes, hand that one back instead of attaching a
            // second copy to the record.
            for (ContentDocumentLink l : [
                SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.CreatedDate
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :linkedFormId
            ]) {
                if (l.ContentDocument != null
                    && l.ContentDocument.Title == title
                    && l.ContentDocument.CreatedDate > System.now().addMinutes(-5)) {
                    return l.ContentDocumentId;
                }
            }

            // Render the Visualforce page as PDF. The VF page reads its
            // data via this controller's constructor (id query param).
            String ns = NeuraFormUtils.getNamespacePrefix();
            String vfName = String.isBlank(ns)
                ? 'NeuraFormReportPDF'
                : ns.replace('__', '') + '__NeuraFormReportPDF';
            PageReference pdfPage = new PageReference('/apex/' + vfName);
            pdfPage.getParameters().put('id', linkedFormId);

            Blob pdfBlob;
            if (Test.isRunningTest()) {
                // getContentAsPDF can't run in test context; use a stub.
                pdfBlob = Blob.valueOf('test-pdf');
            } else {
                pdfBlob = pdfPage.getContentAsPDF();
            }

            ContentVersion cv = new ContentVersion();
            cv.Title = title;
            cv.PathOnClient = fileName;
            cv.VersionData = pdfBlob;
            cv.IsMajorVersion = true;
            insert cv;

            // Re-query to get the ContentDocumentId.
            ContentVersion saved = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :cv.Id LIMIT 1
            ];

            // Link to the Linked_Form AND the parent record so it shows in
            // both Files related lists. allOrNone=false so a failure on the
            // parent (rare — typically a sharing edge case) doesn't kill the
            // whole operation; the LF link is the critical one.
            List<ContentDocumentLink> links = new List<ContentDocumentLink>();
            links.add(makeLink(saved.ContentDocumentId, linkedFormId));
            if (lf.Work_Order__c != null)
                links.add(makeLink(saved.ContentDocumentId, lf.Work_Order__c));
            if (lf.Work_Order_Line_Item__c != null)
                links.add(makeLink(saved.ContentDocumentId, lf.Work_Order_Line_Item__c));
            if (lf.Service_Appointment__c != null)
                links.add(makeLink(saved.ContentDocumentId, lf.Service_Appointment__c));

            Database.insert(links, false);
            return saved.ContentDocumentId;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(
                'PDF generation failed: ' + e.getMessage()
            );
            ahe.setMessage('PDF generation failed: ' + e.getMessage());
            throw ahe;
        }
    }

    private static ContentDocumentLink makeLink(Id contentDocId, Id parentId) {
        ContentDocumentLink l = new ContentDocumentLink();
        l.ContentDocumentId = contentDocId;
        l.LinkedEntityId = parentId;
        l.ShareType = 'V';   // viewer (read-only)
        l.Visibility = 'AllUsers';
        return l;
    }

    // ---- Data loader used by both paths ------------------------------------

    public static ReportData loadReportData(Id linkedFormId) {
        // ReportData's constructor seeds empty collections, false booleans,
        // and stock theme colors, so the bad-id early return below still
        // hands the VF page render-safe data (no null .size(), no
        // 'border: 3px solid ;' from a null color).
        ReportData rd = new ReportData();

        List<Linked_Form__c> lfs = [
            SELECT Id, Name, Status__c, CreatedDate, LastModifiedDate,
                   Form_Template__r.Id, Form_Template__r.Name,
                   Form_Template__r.Scope__c, Account__r.Form_Scope__c,
                   Work_Order__c, Work_Order__r.WorkOrderNumber,
                   Work_Order_Line_Item__c, Service_Appointment__c,
                   Signed_By_Name__c, Signature_Captured_At__c,
                   Signature_Latitude__c, Signature_Longitude__c
            FROM Linked_Form__c
            WHERE Id = :linkedFormId
            LIMIT 1
        ];
        if (lfs.isEmpty()) return rd;
        Linked_Form__c lf = lfs[0];
        rd.linkedFormName = lf.Name;
        rd.status = lf.Status__c;
        rd.completedDate = lf.LastModifiedDate;
        rd.templateName = lf.Form_Template__r?.Name;
        rd.workOrderNumber = lf.Work_Order__r?.WorkOrderNumber;

        // Resolve the brand theme (form -> brand -> global -> stock) so the
        // report renders in the customer's colors with their logo + header.
        // The scope is derived from the row already in hand (Account first,
        // template fallback) — resolveTheme skips getThemeForLinkedForm's
        // repeat query of the same Linked_Form.
        String themeScope = lf.Account__r != null ? lf.Account__r.Form_Scope__c : null;
        if (String.isBlank(themeScope)) {
            themeScope = lf.Form_Template__r != null ? lf.Form_Template__r.Scope__c : null;
        }
        NeuraFormBrandThemeController.Theme theme =
            NeuraFormBrandThemeController.resolveTheme(lf.Form_Template__r?.Id, themeScope);
        rd.brandPrimaryColor = theme.primaryColor;
        rd.brandSecondaryColor = theme.secondaryColor;
        rd.brandLogoUrl = theme.logoUrl;
        rd.brandHeaderText = String.isNotBlank(theme.headerText)
            ? theme.headerText : lf.Form_Template__r?.Name;
        // Stash the customer's output template; merged after the rest of the
        // report data (findings, signature, summary) is assembled below.
        String outputTemplateHtml = theme.outputTemplateHtml;

        // Signature audit context (who/when/where), captured on-site at sign.
        rd.signedByName = lf.Signed_By_Name__c;
        rd.signatureCapturedAt = lf.Signature_Captured_At__c;
        if (lf.Signature_Latitude__c != null && lf.Signature_Longitude__c != null) {
            rd.signatureGeo = lf.Signature_Latitude__c + ', ' + lf.Signature_Longitude__c;
        }
        rd.hasSignature = String.isNotBlank(lf.Signed_By_Name__c)
            || lf.Signature_Captured_At__c != null;

        // Findings (compliance exceptions) - the content that actually matters
        // to the customer, omitted from the original report. Severity is
        // ranked in Apex: ORDER BY Severity__c sorts alphabetically, which
        // put Low above Medium on the customer-facing report.
        Map<String, Integer> severityRank = new Map<String, Integer>{
            'Critical' => 0, 'High' => 1, 'Medium' => 2, 'Low' => 3
        };
        List<List<FindingRow>> severityBuckets = new List<List<FindingRow>>();
        for (Integer i = 0; i <= severityRank.size(); i++) {
            severityBuckets.add(new List<FindingRow>());
        }
        for (Form_Finding__c f : [
            SELECT Severity__c, Status__c, Notes__c,
                   Form_Answer__r.Form_Question__r.Question__c
            FROM Form_Finding__c
            WHERE Linked_Form__c = :linkedFormId
        ]) {
            FindingRow fr = new FindingRow();
            fr.severity = f.Severity__c;
            fr.status = f.Status__c;
            fr.notes = f.Notes__c;
            fr.questionLabel = f.Form_Answer__r.Form_Question__r != null
                ? f.Form_Answer__r.Form_Question__r.Question__c : null;
            Integer rank = severityRank.containsKey(f.Severity__c)
                ? severityRank.get(f.Severity__c) : severityRank.size();
            severityBuckets[rank].add(fr);
        }
        for (List<FindingRow> bucket : severityBuckets) {
            rd.findings.addAll(bucket);
        }

        // Pull questions in display order along with section/page structure.
        Map<Id, Form_Question__c> qById = new Map<Id, Form_Question__c>([
            SELECT Id, Question__c, Type__c, Form_Page__c, Form_Section__c,
                   Order__c, Form_Page__r.Title__c, Form_Page__r.Order__c,
                   Form_Section__r.Title__c, Form_Section__r.Order__c,
                   Form_Section__r.Show_Title__c
            FROM Form_Question__c
            WHERE Form_Template__c = :lf.Form_Template__r.Id
            ORDER BY Form_Page__r.Order__c ASC,
                     Form_Section__r.Order__c ASC,
                     Order__c ASC
        ]);

        List<Form_Answer__c> answers = [
            SELECT Id, Form_Question__c, Answer__c, Related_Comment__c, Type__c
            FROM Form_Answer__c
            WHERE Linked_Form__c = :linkedFormId
        ];
        Map<Id, Form_Answer__c> ansByQ = new Map<Id, Form_Answer__c>();
        for (Form_Answer__c a : answers) ansByQ.put(a.Form_Question__c, a);

        // Group questions → sections → pages.
        Map<Id, Map<Id, List<QuestionRow>>> byPageSection =
            new Map<Id, Map<Id, List<QuestionRow>>>();
        Map<Id, String> pageTitleById = new Map<Id, String>();
        Map<Id, Decimal> pageOrderById = new Map<Id, Decimal>();
        Map<Id, String> sectionTitleById = new Map<Id, String>();
        Map<Id, Decimal> sectionOrderById = new Map<Id, Decimal>();

        for (Form_Question__c q : qById.values()) {
            if (q.Type__c == 'Display Text') continue;
            Form_Answer__c ans = ansByQ.get(q.Id);
            if (ans == null || String.isBlank(ans.Answer__c)) continue;

            QuestionRow row = new QuestionRow();
            row.label = q.Question__c;
            row.value = ans.Answer__c;
            row.comment = ans.Related_Comment__c;
            row.type = q.Type__c;

            Id pid = q.Form_Page__c;
            Id sid = q.Form_Section__c;
            pageTitleById.put(pid, q.Form_Page__r?.Title__c);
            pageOrderById.put(pid, q.Form_Page__r?.Order__c);
            sectionTitleById.put(sid, q.Form_Section__r?.Show_Title__c == true
                ? q.Form_Section__r?.Title__c : null);
            sectionOrderById.put(sid, q.Form_Section__r?.Order__c);

            if (!byPageSection.containsKey(pid)) {
                byPageSection.put(pid, new Map<Id, List<QuestionRow>>());
            }
            if (!byPageSection.get(pid).containsKey(sid)) {
                byPageSection.get(pid).put(sid, new List<QuestionRow>());
            }
            byPageSection.get(pid).get(sid).add(row);
        }

        // Materialize to ordered lists for the VF page.
        List<Id> pageIds = new List<Id>(byPageSection.keySet());
        pageIds.sort();  // Id sort is stable for the same-template id space
        // Re-sort by actual page Order__c.
        pageIds = sortIdsByDecimal(pageIds, pageOrderById);

        rd.pages = new List<PageGroup>();
        for (Id pid : pageIds) {
            PageGroup pg = new PageGroup();
            pg.title = pageTitleById.get(pid);
            pg.sections = new List<SectionGroup>();
            List<Id> sectionIds = new List<Id>(byPageSection.get(pid).keySet());
            sectionIds = sortIdsByDecimal(sectionIds, sectionOrderById);
            for (Id sid : sectionIds) {
                SectionGroup sg = new SectionGroup();
                sg.title = sectionTitleById.get(sid);
                sg.rows = byPageSection.get(pid).get(sid);
                pg.sections.add(sg);
            }
            rd.pages.add(pg);
        }

        // Try to pull a service summary if it's stored on the LF. Field
        // doesn't exist by default; if you've added it (see README), it
        // surfaces here. Wrapped in try to stay deploy-safe.
        try {
            String summaryField = NeuraFormUtils.getNamespacePrefix() + 'Service_Summary__c';
            SObject lfSO = Database.query(
                'SELECT ' + summaryField + ' FROM Linked_Form__c WHERE Id = :linkedFormId LIMIT 1'
            );
            Object sval = lfSO.get(summaryField);
            if (sval != null) rd.serviceSummary = String.valueOf(sval);
        } catch (Exception ignored) {
            rd.serviceSummary = null;
        }

        // If the brand supplied an output template, merge the report data into
        // it now (all the pieces are assembled). Otherwise the VF page falls
        // back to the default fixed layout.
        if (String.isNotBlank(outputTemplateHtml)) {
            rd.renderedHtml = mergeOutputTemplate(outputTemplateHtml, rd);
            rd.hasRenderedHtml = String.isNotBlank(rd.renderedHtml);
        }

        return rd;
    }

    // ---- Output-template token merge ---------------------------------------
    // Replaces {{tokens}} in the stored HTML template with report data. The
    // template is NOT fully trusted: it can be LLM-drafted from a customer
    // document (prompt-injection surface), so it's sanitized before merging.
    // DATA values are HTML-escaped, and the merge is a SINGLE pass over the
    // raw template — substituted values are never re-scanned, so a field
    // user typing "{{answer:Other Question}}" into a note gets literal text
    // in the PDF, not a second substitution.

    @TestVisible
    private static String mergeOutputTemplate(String template, ReportData rd) {
        String html = sanitizeTemplateHtml(template);

        // Simple scalar tokens. Colors come pre-validated as strict hex from
        // NeuraFormBrandThemeController, which is why they may skip esc().
        Map<String, String> tokens = new Map<String, String>{
            'brand.headerText' => esc(rd.brandHeaderText),
            'brand.primaryColor' => rd.brandPrimaryColor,
            'brand.secondaryColor' => rd.brandSecondaryColor,
            'brand.logo' => String.isBlank(rd.brandLogoUrl) ? '' :
                '<img src="' + esc(rd.brandLogoUrl) + '" alt="logo" style="max-height:48px"/>',
            'report.formName' => esc(rd.linkedFormName),
            'report.status' => esc(rd.status),
            'report.workOrder' => esc(rd.workOrderNumber),
            'report.serviceSummary' => esc(rd.serviceSummary),
            'report.completedDate' => rd.completedDate == null ? '' :
                esc(rd.completedDate.format('MMM d, yyyy h:mm a')),
            'answers' => buildAnswersHtml(rd),
            'findings' => buildFindingsHtml(rd),
            'signature' => buildSignatureHtml(rd)
        };

        // Per-question tokens: {{answer:Question Label}} -> that answer's value.
        Map<String, String> answerByLabel = new Map<String, String>();
        if (rd.pages != null) {
            for (PageGroup pg : rd.pages) {
                for (SectionGroup sg : pg.sections) {
                    for (QuestionRow row : sg.rows) {
                        if (row.label != null) answerByLabel.put(row.label.toLowerCase(), row.value);
                    }
                }
            }
        }

        // Single pass: resolve every {{...}} in the template as either a
        // scalar token or an answer token; unknown tokens pass through as
        // literal text so a typo'd token is visible in review.
        Matcher m = Pattern.compile('\\{\\{([^}]+)\\}\\}').matcher(html);
        String out = '';
        Integer last = 0;
        while (m.find()) {
            out += html.substring(last, m.start());
            String name = m.group(1).trim();
            if (name.toLowerCase().startsWith('answer:')) {
                String label = name.substring(7).trim().toLowerCase();
                out += esc(answerByLabel.containsKey(label) ? answerByLabel.get(label) : '');
            } else if (tokens.containsKey(name) && tokens.get(name) != null) {
                out += tokens.get(name);
            } else {
                out += m.group(0);
            }
            last = m.end();
        }
        out += html.substring(last);
        return out;
    }

    /**
     * Strip active content from the stored output template before it hits
     * the escape="false" render: script/iframe/object/embed/link/meta/style
     * tags, inline on* event handlers, and javascript: URLs. A regex pass is
     * not a full HTML parser — it hardens the LLM-drafted-template path
     * (renderAs="pdf" already executes no script), it does not make
     * arbitrary hostile HTML safe for a browser context. Keep the PDF page
     * as the only consumer of this HTML.
     */
    @TestVisible
    private static String sanitizeTemplateHtml(String html) {
        if (String.isBlank(html)) return html;
        String s = html;
        s = s.replaceAll(
            '(?is)<\\s*(script|iframe|object|embed|style)\\b[^>]*>.*?<\\s*/\\s*\\1\\s*>', '');
        s = s.replaceAll('(?is)<\\s*(script|iframe|object|embed|link|meta|style)\\b[^>]*/?>', '');
        s = s.replaceAll('(?is)\\son\\w+\\s*=\\s*("[^"]*"|\'[^\']*\'|[^\\s>]+)', '');
        s = s.replaceAll('(?is)(href|src)\\s*=\\s*(["\']?)\\s*javascript:[^"\'\\s>]*\\2', '$1="#"');
        return s;
    }

    private static String esc(String s) {
        return s == null ? '' : s.escapeHtml4();
    }

    // These emit the SAME class names the VF page's <head> <style> defines
    // (.page-group / .answers / .findings-tbl / .signature-block ...), so the
    // merged blocks pick up the brand-colored page styles whether they land in
    // a brand output template or the fixed layout.
    private static String buildAnswersHtml(ReportData rd) {
        if (rd.pages == null || rd.pages.isEmpty()) return '';
        String h = '';
        for (PageGroup pg : rd.pages) {
            h += '<div class="page-group"><h2>' + esc(pg.title) + '</h2>';
            for (SectionGroup sg : pg.sections) {
                h += '<div class="section-group">';
                if (String.isNotBlank(sg.title)) h += '<h3>' + esc(sg.title) + '</h3>';
                h += '<table class="answers">';
                for (QuestionRow row : sg.rows) {
                    h += '<tr><td class="label">' + esc(row.label) + '</td><td class="value">' + esc(row.value);
                    if (String.isNotBlank(row.comment)) {
                        h += '<span class="comment">Note: ' + esc(row.comment) + '</span>';
                    }
                    h += '</td></tr>';
                }
                h += '</table></div>';
            }
            h += '</div>';
        }
        return h;
    }

    private static String buildFindingsHtml(ReportData rd) {
        if (rd.findings == null || rd.findings.isEmpty()) return '';
        String h = '<table class="findings-tbl"><tr><th>Severity</th><th>Area</th>'
            + '<th>Observation</th><th>Status</th></tr>';
        for (FindingRow f : rd.findings) {
            h += '<tr><td class="sev sev-' + esc(f.severity) + '">' + esc(f.severity) + '</td><td>' + esc(f.questionLabel)
                + '</td><td>' + esc(f.notes) + '</td><td>' + esc(f.status) + '</td></tr>';
        }
        return h + '</table>';
    }

    private static String buildSignatureHtml(ReportData rd) {
        if (rd.hasSignature != true) return '';
        String h = '<div class="signature-block"><div class="sig-name">' + esc(rd.signedByName) + '</div>'
            + '<div class="sig-meta">';
        if (rd.signatureCapturedAt != null) {
            h += 'Signed: ' + esc(rd.signatureCapturedAt.format('MMM d, yyyy h:mm a'));
        }
        if (String.isNotBlank(rd.signatureGeo)) h += '<br/>Location: ' + esc(rd.signatureGeo);
        return h + '</div></div>';
    }

    private static List<Id> sortIdsByDecimal(List<Id> ids, Map<Id, Decimal> orderMap) {
        // Bubble sort is fine — pages/sections are typically < 20.
        Integer n = ids.size();
        for (Integer i = 0; i < n - 1; i++) {
            for (Integer j = 0; j < n - 1 - i; j++) {
                Decimal a = orderMap.get(ids[j]);
                Decimal b = orderMap.get(ids[j + 1]);
                if (a == null) a = 0;
                if (b == null) b = 0;
                if (a > b) {
                    Id tmp = ids[j];
                    ids[j] = ids[j + 1];
                    ids[j + 1] = tmp;
                }
            }
        }
        return ids;
    }

    // ---- DTO classes -------------------------------------------------------

    public class ReportData {
        // Render-safe defaults: the VF page's rendered= expressions call
        // .size() on these collections (VF AND() doesn't short-circuit) and
        // its <style> block interpolates the colors, so none of them may be
        // null even on the bad-id early-return path.
        public ReportData() {
            pages = new List<PageGroup>();
            findings = new List<FindingRow>();
            hasSignature = false;
            hasRenderedHtml = false;
            brandPrimaryColor = NeuraFormBrandThemeController.DEFAULT_PRIMARY;
            brandSecondaryColor = NeuraFormBrandThemeController.DEFAULT_SECONDARY;
        }

        public String linkedFormName { get; set; }
        public String templateName { get; set; }
        public String status { get; set; }
        public Datetime completedDate { get; set; }
        public String workOrderNumber { get; set; }
        public String serviceSummary { get; set; }
        public List<PageGroup> pages { get; set; }
        // Brand theme (Vignette 4)
        public String brandPrimaryColor { get; set; }
        public String brandSecondaryColor { get; set; }
        public String brandLogoUrl { get; set; }
        public String brandHeaderText { get; set; }
        // Findings + signature audit trail
        public List<FindingRow> findings { get; set; }
        public Boolean hasSignature { get; set; }
        public String signedByName { get; set; }
        public Datetime signatureCapturedAt { get; set; }
        public String signatureGeo { get; set; }
        // When the brand has an Output_Template_Html__c, this holds the fully
        // merged HTML; the VF page renders it raw instead of the fixed layout.
        public String renderedHtml { get; set; }
        public Boolean hasRenderedHtml { get; set; }
    }

    public class FindingRow {
        public String severity { get; set; }
        public String status { get; set; }
        public String notes { get; set; }
        public String questionLabel { get; set; }
    }

    public class PageGroup {
        public String title { get; set; }
        public List<SectionGroup> sections { get; set; }
    }

    public class SectionGroup {
        public String title { get; set; }
        public List<QuestionRow> rows { get; set; }
    }

    public class QuestionRow {
        public String label { get; set; }
        public String value { get; set; }
        public String comment { get; set; }
        public String type { get; set; }
    }
}
