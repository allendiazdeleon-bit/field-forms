/**
 * Sends the branded inspection report (the PDF generated at close-out by
 * NeuraFormPdfController) to the people who need it — the brand contact and,
 * optionally, an internal Ops distribution address — the moment the inspector
 * finishes, "before she leaves" (Vignette 4, distribution half).
 *
 * Recipients:
 *   - Brand contact: the first Contact on the inspection's Account that has an
 *     email (same "first contact on the account" convention the anomaly
 *     escalation uses for its brand outreach).
 *   - Ops/manager: FieldForms_Configuration__c.Report_Notification_Email__c,
 *     when set.
 * With no usable recipient the method returns sent=false (skipped) rather than
 * throwing — the caller surfaces "no recipients configured" on the completion
 * screen instead of an error.
 *
 * The email body is brand-themed (header bar in the brand's primary color,
 * brand header text/logo) via NeuraFormBrandThemeController, and the report PDF
 * rides along as a file attachment.
 *
 * Best-effort by contract: the renderer calls this fire-and-forget after the
 * inspection is already saved, so a send failure never rolls back close-out.
 */
public with sharing class NeuraFormReportDistribution {

    public class SendResult {
        @AuraEnabled public Boolean sent = false;
        @AuraEnabled public List<String> recipients = new List<String>();
        @AuraEnabled public String message;
    }

    /**
     * @param linkedFormId      the completed inspection
     * @param contentDocumentId the report PDF's ContentDocument (from
     *                          generatePdfForLinkedForm). Optional — when null,
     *                          the latest PDF attached to the Linked_Form is used.
     */
    @AuraEnabled
    public static SendResult sendBrandedReport(Id linkedFormId, Id contentDocumentId) {
        SendResult result = new SendResult();
        if (linkedFormId == null) {
            throw new AuraHandledException('linkedFormId is required.');
        }

        List<Linked_Form__c> lfs = [
            SELECT Id, Name, Account__c, Account__r.Name, Account__r.Form_Scope__c,
                   Form_Template__c, Form_Template__r.Name, Form_Template__r.Scope__c,
                   Service_Summary__c, Signed_By_Name__c, Signature_Captured_At__c,
                   Status__c
            FROM Linked_Form__c
            WHERE Id = :linkedFormId
            LIMIT 1
        ];
        if (lfs.isEmpty()) {
            throw new AuraHandledException('Linked Form not found.');
        }
        Linked_Form__c lf = lfs[0];

        // ---- Resolve recipients -------------------------------------------
        List<String> toAddresses = new List<String>();
        Set<String> seen = new Set<String>();

        if (lf.Account__c != null) {
            for (Contact c : [
                SELECT Email FROM Contact
                WHERE AccountId = :lf.Account__c AND Email != null
                ORDER BY CreatedDate ASC
                LIMIT 1
            ]) {
                addRecipient(toAddresses, seen, c.Email);
            }
        }

        FieldForms_Configuration__c cfg = FieldForms_Configuration__c.getInstance();
        if (cfg != null) {
            addRecipient(toAddresses, seen, cfg.Report_Notification_Email__c);
        }

        if (toAddresses.isEmpty()) {
            result.sent = false;
            result.message = 'No report recipients configured.';
            return result;
        }

        // ---- Resolve the PDF attachment -----------------------------------
        ContentVersion pdf = loadReportPdf(linkedFormId, contentDocumentId);
        if (pdf == null) {
            // No PDF to attach — don't send a report with nothing in it.
            result.sent = false;
            result.message = 'Report PDF not found for this inspection.';
            return result;
        }

        // ---- Build + send --------------------------------------------------
        NeuraFormBrandThemeController.Theme theme =
            NeuraFormBrandThemeController.resolveTheme(
                lf.Form_Template__c,
                lf.Account__r != null ? lf.Account__r.Form_Scope__c : null
            );

        String accountName = lf.Account__r != null && lf.Account__r.Name != null
            ? lf.Account__r.Name : 'your location';
        String templateName = lf.Form_Template__r != null && lf.Form_Template__r.Name != null
            ? lf.Form_Template__r.Name : 'Inspection';

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(toAddresses);
        msg.setSubject(templateName + ' report — ' + accountName);
        msg.setHtmlBody(buildHtmlBody(theme, accountName, templateName, lf));
        msg.setSaveAsActivity(false);

        Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
        att.setFileName(pdf.PathOnClient != null ? pdf.PathOnClient : (templateName + '.pdf'));
        att.setBody(pdf.VersionData);
        att.setContentType('application/pdf');
        msg.setFileAttachments(new List<Messaging.EmailFileAttachment>{ att });

        // allOrNone=false: a single bad address shouldn't sink the whole send.
        Messaging.SendEmailResult[] sendResults =
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg }, false);

        Boolean ok = sendResults != null && !sendResults.isEmpty() && sendResults[0].isSuccess();
        result.sent = ok;
        result.recipients = ok ? toAddresses : new List<String>();
        if (!ok && sendResults != null && !sendResults.isEmpty()
            && !sendResults[0].getErrors().isEmpty()) {
            result.message = sendResults[0].getErrors()[0].getMessage();
        }
        return result;
    }

    private static void addRecipient(List<String> addrs, Set<String> seen, String email) {
        if (String.isBlank(email)) return;
        String norm = email.trim().toLowerCase();
        if (seen.contains(norm)) return;
        seen.add(norm);
        addrs.add(email.trim());
    }

    /**
     * The report PDF as a ContentVersion (latest version + its binary). Prefers
     * the explicit ContentDocumentId the caller just generated; otherwise picks
     * the most recent PDF linked to the Linked_Form.
     */
    private static ContentVersion loadReportPdf(Id linkedFormId, Id contentDocumentId) {
        if (contentDocumentId != null) {
            List<ContentVersion> cvs = [
                SELECT Title, PathOnClient, VersionData
                FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId AND IsLatest = true
                LIMIT 1
            ];
            if (!cvs.isEmpty()) return cvs[0];
        }

        // Fallback: newest PDF attached to the Linked_Form.
        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink l : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :linkedFormId
        ]) {
            docIds.add(l.ContentDocumentId);
        }
        if (docIds.isEmpty()) return null;

        List<ContentVersion> cvs = [
            SELECT Title, PathOnClient, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds
              AND IsLatest = true
              AND FileExtension = 'pdf'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return cvs.isEmpty() ? null : cvs[0];
    }

    private static String buildHtmlBody(
        NeuraFormBrandThemeController.Theme theme,
        String accountName, String templateName, Linked_Form__c lf
    ) {
        String primary = theme != null && String.isNotBlank(theme.primaryColor)
            ? theme.primaryColor : NeuraFormBrandThemeController.DEFAULT_PRIMARY;
        String headerText = theme != null && String.isNotBlank(theme.headerText)
            ? theme.headerText : templateName;

        String logo = theme != null && String.isNotBlank(theme.logoUrl)
            ? '<img src="' + esc(theme.logoUrl) + '" alt="" height="36" '
              + 'style="display:block;max-height:36px;margin-bottom:8px;border:0;" />'
            : '';

        String summary = String.isNotBlank(lf.Service_Summary__c)
            ? '<p style="margin:0 0 16px;color:#444;">' + esc(lf.Service_Summary__c) + '</p>'
            : '';

        String signature = '';
        if (String.isNotBlank(lf.Signed_By_Name__c)) {
            String signedWhen = lf.Signature_Captured_At__c != null
                ? ' on ' + lf.Signature_Captured_At__c.format() : '';
            signature = '<p style="margin:0 0 16px;color:#666;font-size:13px;">'
                + 'Signed by ' + esc(lf.Signed_By_Name__c) + esc(signedWhen) + '.</p>';
        }

        return ''
            + '<div style="font-family:Arial,Helvetica,sans-serif;max-width:600px;">'
            +   '<div style="background:' + esc(primary) + ';color:#ffffff;'
            +       'padding:16px 20px;border-radius:6px 6px 0 0;">'
            +     logo
            +     '<div style="font-size:18px;font-weight:bold;">' + esc(headerText) + '</div>'
            +   '</div>'
            +   '<div style="border:1px solid #e5e5e5;border-top:0;'
            +       'padding:20px;border-radius:0 0 6px 6px;">'
            +     '<p style="margin:0 0 16px;color:#444;">Hello,</p>'
            +     '<p style="margin:0 0 16px;color:#444;">Please find attached the '
            +       esc(templateName) + ' report for <strong>' + esc(accountName)
            +       '</strong>, completed during our recent visit.</p>'
            +     summary
            +     signature
            +     '<p style="margin:0;color:#444;">Thank you,<br/>The Operations Team</p>'
            +   '</div>'
            + '</div>';
    }

    /** Minimal HTML-attribute/body escaping for the merged-in values. */
    private static String esc(String s) {
        if (s == null) return '';
        return s.replace('&', '&amp;')
                .replace('<', '&lt;')
                .replace('>', '&gt;')
                .replace('"', '&quot;');
    }
}
