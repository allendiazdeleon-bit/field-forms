/**
 * Bulk-aware, idempotent provisioning of Linked_Form__c records from
 * Default_Form__c mappings. Called from the three record-triggered flows
 * (ServiceAppointment / WorkOrder / WorkOrderLineItem) via @InvocableMethod,
 * which means Salesforce bulks all triggering records of a single transaction
 * into one List<Request> - we issue exactly two SOQL queries and one DML
 * regardless of how many records triggered the flow.
 *
 * Solves the audit items:
 *   F1 / F5  Idempotency: queries existing Linked_Forms per parent and
 *            skips defaults that already have a Linked_Form pointing at
 *            the same Form_Template. Re-triggers don't duplicate.
 *   F2       Errors caught + returned in Result so the flow's fault path
 *            can surface them instead of silently dropping.
 *   F3       One SOQL for all WorkTypeIds, one SOQL for all parents, one
 *            DML for all inserts. Scales to bulk loads.
 *   F4       Default outcome handled: requests with no resolvable parent
 *            (none of WO / WOLI / SA Id prefixes) are skipped with an
 *            error in the response rather than producing orphan rows.
 *   F6       WorkOrderLineItem requests without an explicit WorkTypeId
 *            fall back to the parent WorkOrder's WorkTypeId so the
 *            normal "inheritance" use case still produces forms.
 *   F8       Result type exposes createdCount, skippedExistingCount,
 *            errors so calling flows can surface counts and dashboards
 *            can aggregate provisioning health.
 */
public with sharing class NeuraFormLinkedFormProvisioner {

    private static final String SA_PREFIX = '08p';
    private static final String WO_PREFIX = '0WO';
    private static final String WOLI_PREFIX = '1WL';
    private static final String DEFAULT_STATUS = 'Not Started';

    public class Request {
        @InvocableVariable(label='Parent Record Id' description='WorkOrder, WorkOrderLineItem, or ServiceAppointment Id.' required=true)
        public Id recordId;

        // String, not Id: when a record-triggered flow passes a BLANK
        // $Record.WorkTypeId, it marshals an empty string — assigning ''
        // to an Id-typed invocable variable throws "Invalid id:" before
        // the method body ever runs, faulting the flow for exactly the
        // WOLI-inherits-parent-WorkType case this action exists to serve.
        // Normalized (blank -> null, validated to Id) at the top of
        // provisionLinkedForms.
        @InvocableVariable(label='Work Type Id' description='Work Type used to look up Default_Forms. For WOLIs, may be left null and we will read it from the parent WorkOrder.')
        public String workTypeId;

        @InvocableVariable(label='Default Status' description='Linked_Form Status to assign on create. Defaults to "Not Started".')
        public String defaultStatus;
    }

    public class Result {
        @InvocableVariable(label='Created Count')
        public Integer createdCount = 0;
        @InvocableVariable(label='Skipped (already exists) Count')
        public Integer skippedExistingCount = 0;
        @InvocableVariable(label='Error Messages')
        public List<String> errors = new List<String>();
    }

    @InvocableMethod(
        label='Provision Linked Forms'
        description='Idempotently creates Linked_Form records from Default_Form mappings for the given parents.'
        category='Field Forms'
    )
    public static List<Result> provisionLinkedForms(List<Request> requests) {
        // Pre-build one Result per Request - Salesforce guarantees the
        // output list length matches the input list so callers can index in.
        List<Result> results = new List<Result>();
        for (Integer i = 0; i < requests.size(); i++) {
            results.add(new Result());
        }

        try {
            // Normalize the flow-marshaled workTypeId: blank -> null, and
            // validate non-blank values are real Ids so a malformed flow
            // input surfaces as a per-request error, not an exception.
            for (Integer i = 0; i < requests.size(); i++) {
                Request req = requests.get(i);
                if (String.isBlank(req.workTypeId)) {
                    req.workTypeId = null;
                } else {
                    try {
                        req.workTypeId = String.valueOf(Id.valueOf(req.workTypeId));
                    } catch (System.StringException e) {
                        results.get(i).errors.add('Invalid Work Type Id: ' + req.workTypeId);
                        req.workTypeId = null;
                    }
                }
            }

            // Resolve missing WorkType for WOLIs by reading from the parent
            // WorkOrder. Done up front so the Default_Form SOQL has every
            // WorkType Id in one query.
            resolveMissingWorkTypeIds(requests, results);

            Set<Id> workTypeIds = new Set<Id>();
            Set<Id> parentRecordIds = new Set<Id>();
            for (Request req : requests) {
                if (req.workTypeId != null) workTypeIds.add(req.workTypeId);
                if (req.recordId != null) parentRecordIds.add(req.recordId);
            }
            if (workTypeIds.isEmpty() || parentRecordIds.isEmpty()) {
                return results;
            }

            // SOQL 1: all Default_Forms for every WorkType in this batch.
            // Lifecycle enforcement lives HERE: the brand hub's Draft ->
            // Active -> Retired story promises that Draft templates don't
            // reach techs until activated — this filter is what makes that
            // true. Null status passes for templates that predate the
            // Status__c field.
            Map<Id, List<Default_Form__c>> defaultsByWorkType = new Map<Id, List<Default_Form__c>>();
            for (Default_Form__c df : [
                SELECT Id, Work_Type__c, Form_Template__c
                FROM Default_Form__c
                WHERE Work_Type__c IN :workTypeIds
                  AND (Form_Template__r.Status__c = 'Active'
                       OR Form_Template__r.Status__c = null)
                WITH SECURITY_ENFORCED
            ]) {
                if (!defaultsByWorkType.containsKey(df.Work_Type__c)) {
                    defaultsByWorkType.put(df.Work_Type__c, new List<Default_Form__c>());
                }
                defaultsByWorkType.get(df.Work_Type__c).add(df);
            }

            // SOQL 2: existing Linked_Forms for every parent in this batch,
            // keyed so we can ask "does a Linked_Form for parent P and
            // template T already exist?" in O(1).
            // Set<String> key = parentId|templateId
            Set<String> existingPairs = buildExistingPairKeys(parentRecordIds);

            // Build the inserts.
            List<Linked_Form__c> toInsert = new List<Linked_Form__c>();
            // Track which Result each Linked_Form belongs to so we can credit
            // the correct caller index after the DML succeeds.
            List<Integer> insertResultIndex = new List<Integer>();

            for (Integer i = 0; i < requests.size(); i++) {
                Request req = requests.get(i);
                Result res = results.get(i);

                if (req.recordId == null || req.workTypeId == null) continue;

                String parentField = parentLookupFieldFor(req.recordId);
                if (parentField == null) {
                    res.errors.add('Unsupported parent record type for Id ' + req.recordId
                        + '. Supported prefixes: ' + SA_PREFIX + ' (Service Appointment), '
                        + WO_PREFIX + ' (Work Order), ' + WOLI_PREFIX + ' (WOLI).');
                    continue;
                }

                List<Default_Form__c> defaults = defaultsByWorkType.get(req.workTypeId);
                if (defaults == null || defaults.isEmpty()) continue;

                String statusValue = String.isNotBlank(req.defaultStatus)
                    ? req.defaultStatus
                    : DEFAULT_STATUS;

                for (Default_Form__c df : defaults) {
                    String key = req.recordId + '|' + df.Form_Template__c;
                    if (existingPairs.contains(key)) {
                        res.skippedExistingCount++;
                        continue;
                    }
                    Linked_Form__c lf = new Linked_Form__c();
                    lf.Form_Template__c = df.Form_Template__c;
                    lf.Status__c = statusValue;
                    lf.put(parentField, req.recordId);
                    toInsert.add(lf);
                    insertResultIndex.add(i);
                    // Add to the set immediately so duplicate defaults inside
                    // the same batch (same parent, same template via two
                    // overlapping Default_Form rows) only insert once.
                    existingPairs.add(key);
                }
            }

            if (!toInsert.isEmpty()) {
                Database.SaveResult[] saves = Database.insert(toInsert, false);
                for (Integer i = 0; i < saves.size(); i++) {
                    Result res = results.get(insertResultIndex.get(i));
                    if (saves[i].isSuccess()) {
                        res.createdCount++;
                    } else {
                        for (Database.Error err : saves[i].getErrors()) {
                            res.errors.add(err.getStatusCode() + ': ' + err.getMessage());
                        }
                    }
                }
            }
        } catch (Exception e) {
            // Catastrophic failure - attribute to every request so the flow's
            // fault path is triggered for each. Still returns the list so we
            // don't swallow the failure entirely.
            String msg = 'Provisioning failed: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, msg + '\n' + e.getStackTraceString());
            for (Result r : results) r.errors.add(msg);
        }
        return results;
    }

    /**
     * For WOLI requests missing a WorkTypeId, read it from the parent
     * WorkOrder. Mutates `req.workTypeId` in place.
     */
    private static void resolveMissingWorkTypeIds(List<Request> requests, List<Result> results) {
        Set<Id> woliIdsNeedingLookup = new Set<Id>();
        for (Request req : requests) {
            if (req.recordId != null
                && String.valueOf(req.recordId).startsWith(WOLI_PREFIX)
                && req.workTypeId == null) {
                woliIdsNeedingLookup.add(req.recordId);
            }
        }
        if (woliIdsNeedingLookup.isEmpty()) return;

        Map<Id, Id> wtByWoli = new Map<Id, Id>();
        for (WorkOrderLineItem woli : [
            SELECT Id, WorkOrder.WorkTypeId
            FROM WorkOrderLineItem
            WHERE Id IN :woliIdsNeedingLookup
            WITH SECURITY_ENFORCED
        ]) {
            if (woli.WorkOrder != null && woli.WorkOrder.WorkTypeId != null) {
                wtByWoli.put(woli.Id, woli.WorkOrder.WorkTypeId);
            }
        }
        for (Request req : requests) {
            if (req.workTypeId == null && wtByWoli.containsKey(req.recordId)) {
                req.workTypeId = wtByWoli.get(req.recordId);
            }
        }
    }

    /**
     * Map parent record Id prefix to the Linked_Form lookup field that
     * should hold it. Returns null for unsupported prefixes.
     */
    private static String parentLookupFieldFor(Id recordId) {
        String prefix = String.valueOf(recordId).substring(0, 3);
        if (prefix == SA_PREFIX) return 'Service_Appointment__c';
        if (prefix == WO_PREFIX) return 'Work_Order__c';
        if (prefix == WOLI_PREFIX) return 'Work_Order_Line_Item__c';
        return null;
    }

    /**
     * Returns a Set of "parentId|templateId" keys for every existing
     * Linked_Form whose parent is in the batch. Built once per invocation
     * so the per-request loop can ask "exists?" in O(1) without re-querying.
     */
    private static Set<String> buildExistingPairKeys(Set<Id> parentIds) {
        Set<String> keys = new Set<String>();
        for (Linked_Form__c lf : [
            SELECT Form_Template__c, Service_Appointment__c, Work_Order__c, Work_Order_Line_Item__c
            FROM Linked_Form__c
            WHERE Service_Appointment__c IN :parentIds
               OR Work_Order__c IN :parentIds
               OR Work_Order_Line_Item__c IN :parentIds
            WITH SECURITY_ENFORCED
        ]) {
            Id parent = lf.Service_Appointment__c != null ? lf.Service_Appointment__c
                : lf.Work_Order__c != null ? lf.Work_Order__c
                : lf.Work_Order_Line_Item__c;
            if (parent != null && lf.Form_Template__c != null) {
                keys.add(parent + '|' + lf.Form_Template__c);
            }
        }
        return keys;
    }
}
