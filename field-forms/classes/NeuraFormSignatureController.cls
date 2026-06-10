/**
 * Stamps the on-site signature audit context (who signed, when, and where)
 * onto a Linked_Form at close-out (Vignette 4). The signature IMAGE itself is
 * captured via the existing Signature question type (stored as a ContentVersion
 * on its Form_Answer); this records the chain-of-custody metadata that pairs
 * with it. Called from the renderer's "Sign On Site" action with the device
 * geolocation + signer name.
 */
public with sharing class NeuraFormSignatureController {

    @AuraEnabled
    public static void captureSignatureContext(
        Id linkedFormId, String signedByName, Decimal latitude, Decimal longitude
    ) {
        if (linkedFormId == null) {
            throw new AuraHandledException('linkedFormId is required.');
        }
        // This is the chain-of-custody record for a signed compliance
        // document — once stamped it must not be silently re-stamped by
        // anyone with record access.
        List<Linked_Form__c> existing = [
            SELECT Signature_Captured_At__c
            FROM Linked_Form__c
            WHERE Id = :linkedFormId
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            throw new AuraHandledException('Linked Form not found.');
        }
        if (existing[0].Signature_Captured_At__c != null) {
            throw new AuraHandledException('This form is already signed.');
        }
        Linked_Form__c lf = new Linked_Form__c(
            Id = linkedFormId,
            Signed_By_Name__c = signedByName,
            Signature_Captured_At__c = System.now(),
            Signature_Latitude__c = latitude,
            Signature_Longitude__c = longitude
        );
        try {
            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.UPDATABLE, new List<Linked_Form__c>{ lf }
            );
            update decision.getRecords();
        } catch (DmlException e) {
            throw new AuraHandledException('Could not record signature context: ' + e.getMessage());
        }
    }
}
