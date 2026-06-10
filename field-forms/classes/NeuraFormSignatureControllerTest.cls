@isTest
private class NeuraFormSignatureControllerTest {
    @isTest
    static void stampsSignatureContext() {
        Form_Template__c t = new Form_Template__c(Name='Sig Test'); insert t;
        Linked_Form__c lf = new Linked_Form__c(Form_Template__c=t.Id, Status__c='Completed'); insert lf;
        Test.startTest();
        NeuraFormSignatureController.captureSignatureContext(lf.Id, 'Store Manager', 33.7490, -84.3880);
        Test.stopTest();
        Linked_Form__c r = [SELECT Signed_By_Name__c, Signature_Captured_At__c,
            Signature_Latitude__c, Signature_Longitude__c FROM Linked_Form__c WHERE Id=:lf.Id];
        System.assertEquals('Store Manager', r.Signed_By_Name__c);
        System.assertNotEquals(null, r.Signature_Captured_At__c);
        System.assertEquals(33.7490, r.Signature_Latitude__c);
        System.assertEquals(-84.3880, r.Signature_Longitude__c);
    }
    @isTest
    static void requiresLinkedFormId() {
        Boolean threw=false;
        try { NeuraFormSignatureController.captureSignatureContext(null,'x',1,1); }
        catch(AuraHandledException e){ threw=true; }
        System.assert(threw);
    }
    @isTest
    static void rejectsReSigning() {
        Form_Template__c t = new Form_Template__c(Name='Sig Test'); insert t;
        Linked_Form__c lf = new Linked_Form__c(Form_Template__c=t.Id, Status__c='Completed'); insert lf;
        NeuraFormSignatureController.captureSignatureContext(lf.Id, 'Store Manager', 33.7490, -84.3880);

        Boolean threw=false;
        try { NeuraFormSignatureController.captureSignatureContext(lf.Id, 'Someone Else', 0, 0); }
        catch(AuraHandledException e){ threw=true; }
        System.assert(threw, 'The chain-of-custody stamp must not be silently overwritten.');

        Linked_Form__c r = [SELECT Signed_By_Name__c FROM Linked_Form__c WHERE Id=:lf.Id];
        System.assertEquals('Store Manager', r.Signed_By_Name__c, 'Original signer preserved.');
    }
}
