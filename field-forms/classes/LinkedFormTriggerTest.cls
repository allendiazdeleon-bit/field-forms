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
}
