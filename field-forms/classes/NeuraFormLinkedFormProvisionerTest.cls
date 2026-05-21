/**
 * Coverage for the bulk/idempotent Linked_Form provisioner. Exercises:
 *   - Happy path: create one Linked_Form per Default_Form
 *   - Idempotency: re-running on the same parent doesn't duplicate
 *   - Bulk: many parents in one invocation use one SOQL batch
 *   - WOLI WorkType inheritance: WOLI with null WorkTypeId falls back to
 *     its parent WorkOrder's
 *   - Unsupported parent prefix: error in Result, no DML
 *   - Empty / null inputs: graceful no-op
 */
@isTest
private class NeuraFormLinkedFormProvisionerTest {

    private static WorkType buildWorkType() {
        WorkType wt = new WorkType(Name = 'Test WT', EstimatedDuration = 1);
        insert wt;
        return wt;
    }

    private static Form_Template__c buildTemplate(String name) {
        Form_Template__c t = new Form_Template__c(Name = name);
        insert t;
        return t;
    }

    private static Default_Form__c buildDefaultForm(Id workTypeId, Id templateId) {
        Default_Form__c df = new Default_Form__c(
            Work_Type__c = workTypeId,
            Form_Template__c = templateId
        );
        insert df;
        return df;
    }

    private static WorkOrder buildWorkOrder(Id workTypeId) {
        WorkOrder wo = new WorkOrder(WorkTypeId = workTypeId);
        insert wo;
        return wo;
    }

    @isTest static void provisionsLinkedFormsForWorkOrder() {
        WorkType wt = buildWorkType();
        Form_Template__c t1 = buildTemplate('T1');
        Form_Template__c t2 = buildTemplate('T2');
        buildDefaultForm(wt.Id, t1.Id);
        buildDefaultForm(wt.Id, t2.Id);
        WorkOrder wo = buildWorkOrder(wt.Id);

        NeuraFormLinkedFormProvisioner.Request req = new NeuraFormLinkedFormProvisioner.Request();
        req.recordId = wo.Id;
        req.workTypeId = wt.Id;

        Test.startTest();
        List<NeuraFormLinkedFormProvisioner.Result> results =
            NeuraFormLinkedFormProvisioner.provisionLinkedForms(
                new List<NeuraFormLinkedFormProvisioner.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(2, results[0].createdCount, 'Both defaults should create Linked_Forms');
        System.assertEquals(0, results[0].skippedExistingCount);
        System.assertEquals(0, results[0].errors.size());
        System.assertEquals(2, [SELECT COUNT() FROM Linked_Form__c WHERE Work_Order__c = :wo.Id]);
    }

    @isTest static void isIdempotent() {
        WorkType wt = buildWorkType();
        Form_Template__c t = buildTemplate('T');
        buildDefaultForm(wt.Id, t.Id);
        WorkOrder wo = buildWorkOrder(wt.Id);

        NeuraFormLinkedFormProvisioner.Request req = new NeuraFormLinkedFormProvisioner.Request();
        req.recordId = wo.Id;
        req.workTypeId = wt.Id;

        // First pass creates.
        NeuraFormLinkedFormProvisioner.provisionLinkedForms(
            new List<NeuraFormLinkedFormProvisioner.Request>{ req }
        );

        Test.startTest();
        // Second pass should detect the existing Linked_Form and skip.
        List<NeuraFormLinkedFormProvisioner.Result> results =
            NeuraFormLinkedFormProvisioner.provisionLinkedForms(
                new List<NeuraFormLinkedFormProvisioner.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(0, results[0].createdCount, 'Second pass should not create duplicates');
        System.assertEquals(1, results[0].skippedExistingCount, 'Should report the skip');
        System.assertEquals(1, [SELECT COUNT() FROM Linked_Form__c WHERE Work_Order__c = :wo.Id],
            'Still only one Linked_Form after two invocations');
    }

    @isTest static void bulkInvocationUsesOneQuery() {
        WorkType wt = buildWorkType();
        Form_Template__c t = buildTemplate('T');
        buildDefaultForm(wt.Id, t.Id);

        List<WorkOrder> wos = new List<WorkOrder>();
        for (Integer i = 0; i < 50; i++) {
            wos.add(new WorkOrder(WorkTypeId = wt.Id));
        }
        insert wos;

        List<NeuraFormLinkedFormProvisioner.Request> reqs =
            new List<NeuraFormLinkedFormProvisioner.Request>();
        for (WorkOrder wo : wos) {
            NeuraFormLinkedFormProvisioner.Request r = new NeuraFormLinkedFormProvisioner.Request();
            r.recordId = wo.Id;
            r.workTypeId = wt.Id;
            reqs.add(r);
        }

        Test.startTest();
        Integer soqlBefore = Limits.getQueries();
        List<NeuraFormLinkedFormProvisioner.Result> results =
            NeuraFormLinkedFormProvisioner.provisionLinkedForms(reqs);
        Integer soqlUsed = Limits.getQueries() - soqlBefore;
        Test.stopTest();

        System.assertEquals(50, results.size());
        for (NeuraFormLinkedFormProvisioner.Result r : results) {
            System.assertEquals(1, r.createdCount);
        }
        // Two query SOQL pattern: one for Default_Forms, one for existing
        // Linked_Forms (plus the optional WOLI parent lookup, which doesn't
        // run for WorkOrder requests).
        System.assert(soqlUsed <= 3,
            'Bulk path should use at most ~3 SOQL queries regardless of batch size, used ' + soqlUsed);
    }

    @isTest static void woliFallsBackToParentWorkType() {
        WorkType wt = buildWorkType();
        Form_Template__c t = buildTemplate('T');
        buildDefaultForm(wt.Id, t.Id);
        WorkOrder wo = buildWorkOrder(wt.Id);
        // The WOLI itself has no WorkTypeId set; we expect the provisioner
        // to inherit it from the parent WorkOrder.
        WorkOrderLineItem woli = new WorkOrderLineItem(
            WorkOrderId = wo.Id,
            // WOLI requires a Product2 OR LineItemNumber; minimal valid shape.
            Description = 'Test WOLI'
        );
        insert woli;

        NeuraFormLinkedFormProvisioner.Request req = new NeuraFormLinkedFormProvisioner.Request();
        req.recordId = woli.Id;
        // workTypeId intentionally null - inheritance path.

        Test.startTest();
        List<NeuraFormLinkedFormProvisioner.Result> results =
            NeuraFormLinkedFormProvisioner.provisionLinkedForms(
                new List<NeuraFormLinkedFormProvisioner.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results[0].createdCount,
            'WOLI without explicit WorkTypeId should inherit from parent WO');
    }

    @isTest static void unsupportedParentPrefixReturnsError() {
        // Account Id starts with 001, not one of our supported prefixes.
        Account a = new Account(Name = 'Test');
        insert a;
        WorkType wt = buildWorkType();
        Form_Template__c t = buildTemplate('T');
        buildDefaultForm(wt.Id, t.Id);

        NeuraFormLinkedFormProvisioner.Request req = new NeuraFormLinkedFormProvisioner.Request();
        req.recordId = a.Id;
        req.workTypeId = wt.Id;

        Test.startTest();
        List<NeuraFormLinkedFormProvisioner.Result> results =
            NeuraFormLinkedFormProvisioner.provisionLinkedForms(
                new List<NeuraFormLinkedFormProvisioner.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(0, results[0].createdCount);
        System.assert(!results[0].errors.isEmpty(),
            'Unsupported parent should produce an error in the Result');
        System.assertEquals(0, [SELECT COUNT() FROM Linked_Form__c]);
    }

    @isTest static void emptyInputsAreNoOp() {
        NeuraFormLinkedFormProvisioner.Request req = new NeuraFormLinkedFormProvisioner.Request();
        // Both recordId and workTypeId null.
        List<NeuraFormLinkedFormProvisioner.Result> results =
            NeuraFormLinkedFormProvisioner.provisionLinkedForms(
                new List<NeuraFormLinkedFormProvisioner.Request>{ req }
            );
        System.assertEquals(1, results.size());
        System.assertEquals(0, results[0].createdCount);
        System.assertEquals(0, results[0].errors.size(),
            'Null inputs should be a no-op, not an error');
    }

    @isTest static void customDefaultStatusIsApplied() {
        WorkType wt = buildWorkType();
        Form_Template__c t = buildTemplate('T');
        buildDefaultForm(wt.Id, t.Id);
        WorkOrder wo = buildWorkOrder(wt.Id);

        NeuraFormLinkedFormProvisioner.Request req = new NeuraFormLinkedFormProvisioner.Request();
        req.recordId = wo.Id;
        req.workTypeId = wt.Id;
        req.defaultStatus = 'In Progress';

        Test.startTest();
        NeuraFormLinkedFormProvisioner.provisionLinkedForms(
            new List<NeuraFormLinkedFormProvisioner.Request>{ req }
        );
        Test.stopTest();

        Linked_Form__c created = [SELECT Status__c FROM Linked_Form__c WHERE Work_Order__c = :wo.Id LIMIT 1];
        System.assertEquals('In Progress', created.Status__c);
    }
}
