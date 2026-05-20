trigger FormQuestionTrigger on Form_Question__c (after insert, after update, after delete) {
    Set<Id> parentIds = new Set<Id>();
    
    if (Trigger.isAfter) {
        if (Trigger.isInsert || Trigger.isUpdate) {
            for (Form_Question__c record : Trigger.new) {
                parentIds.add(record.Form_Template__c);
            }
        } else if (Trigger.isDelete) {
            for (Form_Question__c record : Trigger.old) {
                parentIds.add(record.Form_Template__c);
            }
        }
    }
    
    // Get custom setting FieldForms_Configuration__c to determine if disable switch is on Disable_Form_Template_JSON_Trigger__c
    FieldForms_Configuration__c mySetting = FieldForms_Configuration__c.getInstance();

    // Access the value of the field
    if(!mySetting.Disable_Form_Template_JSON_Trigger__c){
        NeuraFormLogic.enqueueSnapshotRebuild(parentIds);
    }
}