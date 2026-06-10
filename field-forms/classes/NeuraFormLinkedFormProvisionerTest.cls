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

    // Direct-invocable tests insert the WorkOrder WITHOUT a WorkTypeId and
    // pass workTypeId in the Request instead: the Work Order record-triggered
    // flow provisions on create when a WorkType is present, which would make
    // the direct call under test an idempotent no-op (created=0).
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
        WorkOrder wo = buildWorkOrder(null);

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
        WorkOrder wo = buildWorkOrder(null);

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
            wos.add(new WorkOrder()); // no WorkTypeId: keep the WO flow out
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
        // The WOLI itself has no WorkTypeId; the WOLI flow fires on create
        // and the provisioner inherits the WorkType from the parent WO.
        // (This end-to-end path was dead until the flow entry formula was
        // fixed — ISNEW() isn't a flow-formula function.)
        WorkOrderLineItem woli = new WorkOrderLineItem(
            WorkOrderId = wo.Id,
            Description = 'Test WOLI'
        );
        insert woli;

        System.assertEquals(1,
            [SELECT COUNT() FROM Linked_Form__c WHERE Work_Order_Line_Item__c = :woli.Id],
            'The WOLI flow + parent-WorkType fallback should provision on create');

        // A direct re-invocation must be idempotent, not duplicate.
        NeuraFormLinkedFormProvisioner.Request req = new NeuraFormLinkedFormProvisioner.Request();
        req.recordId = woli.Id;
        // workTypeId intentionally null - inheritance path.

        Test.startTest();
        List<NeuraFormLinkedFormProvisioner.Result> results =
            NeuraFormLinkedFormProvisioner.provisionLinkedForms(
                new List<NeuraFormLinkedFormProvisioner.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(0, results[0].createdCount);
        System.assertEquals(1, results[0].skippedExistingCount,
            'Re-running on an already-provisioned WOLI skips, never duplicates');
        System.assertEquals(1,
            [SELECT COUNT() FROM Linked_Form__c WHERE Work_Order_Line_Item__c = :woli.Id]);
    }

    @isTest static void draftAndRetiredTemplatesDoNotProvision() {
        WorkType wt = buildWorkType();
        Form_Template__c draft = buildTemplate('Draft T');
        draft.Status__c = 'Draft';
        Form_Template__c retired = buildTemplate('Retired T');
        retired.Status__c = 'Retired';
        Form_Template__c active = buildTemplate('Active T');
        active.Status__c = 'Active';
        update new List<Form_Template__c>{ draft, retired, active };
        buildDefaultForm(wt.Id, draft.Id);
        buildDefaultForm(wt.Id, retired.Id);
        buildDefaultForm(wt.Id, active.Id);
        WorkOrder wo = buildWorkOrder(null);

        NeuraFormLinkedFormProvisioner.Request req = new NeuraFormLinkedFormProvisioner.Request();
        req.recordId = wo.Id;
        req.workTypeId = wt.Id;

        Test.startTest();
        List<NeuraFormLinkedFormProvisioner.Result> results =
            NeuraFormLinkedFormProvisioner.provisionLinkedForms(
                new List<NeuraFormLinkedFormProvisioner.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results[0].createdCount,
            'Only the Active template provisions — Draft/Retired stay off techs\' phones, as the brand hub lifecycle promises.');
        List<Linked_Form__c> created = [
            SELECT Form_Template__c FROM Linked_Form__c WHERE Work_Order__c = :wo.Id
        ];
        System.assertEquals(1, created.size());
        System.assertEquals(active.Id, created[0].Form_Template__c);
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
        WorkOrder wo = buildWorkOrder(null);

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
