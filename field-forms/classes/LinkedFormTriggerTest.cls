/**
 * Tests for LinkedFormTrigger — Visit_Date__c stamping on completion.
 */
@isTest
private class LinkedFormTriggerTest {

    private static Form_Template__c tpl() {
        Form_Template__c t = new Form_Template__c(Name = 'Visit Date Test');
        insert t;
        return t;
    }

    @isTest
    static void stampsVisitDateWhenCompletedOnUpdate() {
        Linked_Form__c lf = new Linked_Form__c(
            Form_Template__c = tpl().Id, Status__c = 'In Progress'
        );
        insert lf;
        System.assertEquals(null,
            [SELECT Visit_Date__c FROM Linked_Form__c WHERE Id = :lf.Id].Visit_Date__c);

        lf.Status__c = 'Completed';
        update lf;

        System.assertEquals(Date.today(),
            [SELECT Visit_Date__c FROM Linked_Form__c WHERE Id = :lf.Id].Visit_Date__c);
    }

    @isTest
    static void stampsVisitDateWhenInsertedCompleted() {
        Linked_Form__c lf = new Linked_Form__c(
            Form_Template__c = tpl().Id, Status__c = 'Completed'
        );
        insert lf;
        System.assertEquals(Date.today(),
            [SELECT Visit_Date__c FROM Linked_Form__c WHERE Id = :lf.Id].Visit_Date__c);
    }

    @isTest
    static void preservesExplicitVisitDate() {
        Date backfilled = Date.today().addDays(-30);
        Linked_Form__c lf = new Linked_Form__c(
            Form_Template__c = tpl().Id, Status__c = 'Completed',
            Visit_Date__c = backfilled
        );
        insert lf;
        System.assertEquals(backfilled,
            [SELECT Visit_Date__c FROM Linked_Form__c WHERE Id = :lf.Id].Visit_Date__c,
            'An explicitly set date (backfill/import) must not be overwritten.');
    }

    @isTest
    static void stampsLifecycleAnalyticsFacts() {
        Linked_Form__c lf = new Linked_Form__c(
            Form_Template__c = tpl().Id, Status__c = 'Not Started'
        );
        insert lf;

        lf.Status__c = 'In Progress';
        update lf;
        lf = [SELECT Started_At__c FROM Linked_Form__c WHERE Id = :lf.Id];
        System.assertNotEquals(null, lf.Started_At__c, 'Start of work is stamped.');

        lf.Status__c = 'Completed';
        update lf;
        lf = [
            SELECT Started_At__c, Completed_At__c, Completed_By__c, Fill_Duration_Minutes__c
            FROM Linked_Form__c WHERE Id = :lf.Id
        ];
        System.assertNotEquals(null, lf.Completed_At__c);
        System.assertEquals(UserInfo.getUserId(), lf.Completed_By__c,
            'The completing user is the inspector dimension.');
        System.assertNotEquals(null, lf.Fill_Duration_Minutes__c,
            'Duration computes when both timestamps exist.');
        System.assert(lf.Fill_Duration_Minutes__c >= 0);
    }

    @isTest
    static void answersInheritCatalogIdentity() {
        Form_Template__c t = tpl();
        Form_Page__c page = new Form_Page__c(Name = 'P', Order__c = 1, Title__c = 'P', Form_Template__c = t.Id);
        insert page;
        Form_Section__c section = new Form_Section__c(Name = 'S', Order__c = 1, Title__c = 'S', Form_Template__c = t.Id, Form_Page__c = page.Id);
        insert section;
        Form_Question__c q = new Form_Question__c(
            Question__c = 'Door seal status', Type__c = 'Text', Order__c = 1,
            Form_Template__c = t.Id, Form_Page__c = page.Id, Form_Section__c = section.Id
        );
        insert q;
        Id catId = neuraFormBuilderController.createCatalogEntryForBinding(q.Id);
        Linked_Form__c lf = new Linked_Form__c(Form_Template__c = t.Id, Status__c = 'In Progress');
        insert lf;

        Form_Answer__c a = new Form_Answer__c(
            Linked_Form__c = lf.Id, Form_Question__c = q.Id,
            Answer__c = 'Worn', Type__c = 'Text'
        );
        insert a;

        System.assertEquals(catId,
            [SELECT Form_Question_Catalog__c FROM Form_Answer__c WHERE Id = :a.Id].Form_Question_Catalog__c,
            'Answers carry the stable question identity for cross-version analytics.');
    }
}