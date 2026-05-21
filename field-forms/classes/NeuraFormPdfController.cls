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
            String fileName = (tplName + ' - ' + lf.Name + '.pdf')
                .replaceAll('[\\\\/:*?"<>|]', '_');

            ContentVersion cv = new ContentVersion();
            cv.Title = tplName + ' - ' + lf.Name;
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
        ReportData rd = new ReportData();

        List<Linked_Form__c> lfs = [
            SELECT Id, Name, Status__c, CreatedDate, LastModifiedDate,
                   Form_Template__r.Id, Form_Template__r.Name,
                   Work_Order__c, Work_Order__r.WorkOrderNumber,
                   Work_Order_Line_Item__c, Service_Appointment__c
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

        return rd;
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
        public String linkedFormName { get; set; }
        public String templateName { get; set; }
        public String status { get; set; }
        public Datetime completedDate { get; set; }
        public String workOrderNumber { get; set; }
        public String serviceSummary { get; set; }
        public List<PageGroup> pages { get; set; }
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
