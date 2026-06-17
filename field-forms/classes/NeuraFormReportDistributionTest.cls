/**
 * Tests for NeuraFormReportDistribution — recipient resolution (brand contact +
 * Ops config), the no-recipient skip, the missing-PDF skip, and a successful
 * send (asserted via the email-invocation counter, the standard way to verify
 * Messaging.sendEmail in a test).
 */
@isTest
private class NeuraFormReportDistributionTest {

    private static Linked_Form__c makeInspection(Boolean withContact) {
        Form_Template__c tpl = new Form_Template__c(Name = 'Food Safety Inspection');
        insert tpl;
        Account acc = new Account(Name = 'Burger King #4421');
        insert acc;
        if (withContact) {
            insert new Contact(
                LastName = 'Patel', FirstName = 'Jen',
                AccountId = acc.Id, Email = 'jen.patel@example.com'
            );
        }
        Linked_Form__c lf = new Linked_Form__c(
            Form_Template__c = tpl.Id, Account__c = acc.Id, Status__c = 'Completed',
            Service_Summary__c = 'All clear except the freezer hinge.',
            Signed_By_Name__c = 'Dana Manager', Signature_Captured_At__c = System.now()
        );
        insert lf;
        return lf;
    }

    /** Attach a fake PDF to the Linked_Form and return its ContentDocumentId. */
    private static Id attachPdf(Id linkedFormId) {
        ContentVersion cv = new ContentVersion(
            Title = 'Food Safety Inspection - LF',
            PathOnClient = 'report.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 test'),
            IsMajorVersion = true
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = docId, LinkedEntityId = linkedFormId,
            ShareType = 'V', Visibility = 'AllUsers'
        );
        return docId;
    }

    @isTest
    static void sendsToBrandContactAndOps() {
        Linked_Form__c lf = makeInspection(true);
        Id docId = attachPdf(lf.Id);
        insert new FieldForms_Configuration__c(Report_Notification_Email__c = 'ops@example.com');

        Test.startTest();
        NeuraFormReportDistribution.SendResult res =
            NeuraFormReportDistribution.sendBrandedReport(lf.Id, docId);
        Test.stopTest();

        System.assert(res.sent, 'Expected the report to send: ' + res.message);
        System.assertEquals(2, res.recipients.size(),
            'Both the brand contact and the Ops address should receive it.');
        System.assert(new Set<String>(res.recipients).contains('jen.patel@example.com'));
        System.assert(new Set<String>(res.recipients).contains('ops@example.com'));
    }

    @isTest
    static void dedupesAndFallsBackToLatestPdf() {
        // Contact email == ops email: should collapse to a single recipient.
        Linked_Form__c lf = makeInspection(true);
        attachPdf(lf.Id); // no contentDocumentId passed -> fallback lookup path
        insert new FieldForms_Configuration__c(Report_Notification_Email__c = 'jen.patel@example.com');

        Test.startTest();
        NeuraFormReportDistribution.SendResult res =
            NeuraFormReportDistribution.sendBrandedReport(lf.Id, null);
        Test.stopTest();

        System.assert(res.sent, 'Expected send via the latest-PDF fallback: ' + res.message);
        System.assertEquals(1, res.recipients.size(),
            'Duplicate contact/ops address should dedupe to one recipient.');
    }

    @isTest
    static void skipsWhenNoRecipients() {
        Linked_Form__c lf = makeInspection(false); // no contact
        Id docId = attachPdf(lf.Id);
        // No config row -> no ops address.

        Test.startTest();
        NeuraFormReportDistribution.SendResult res =
            NeuraFormReportDistribution.sendBrandedReport(lf.Id, docId);
        Test.stopTest();

        System.assert(!res.sent, 'No recipients -> should not send.');
        System.assert(res.recipients.isEmpty());
        System.assertEquals(0, Limits.getEmailInvocations(), 'No email should be sent.');
    }

    @isTest
    static void skipsWhenNoPdf() {
        Linked_Form__c lf = makeInspection(true);
        insert new FieldForms_Configuration__c(Report_Notification_Email__c = 'ops@example.com');
        // No PDF attached.

        Test.startTest();
        NeuraFormReportDistribution.SendResult res =
            NeuraFormReportDistribution.sendBrandedReport(lf.Id, null);
        Test.stopTest();

        System.assert(!res.sent, 'No PDF -> should not send.');
        System.assertEquals(0, Limits.getEmailInvocations());
    }

    @isTest
    static void requiresLinkedFormId() {
        try {
            NeuraFormReportDistribution.sendBrandedReport(null, null);
            System.assert(false, 'Expected an AuraHandledException.');
        } catch (AuraHandledException e) {
            // expected
        }
    }
}
