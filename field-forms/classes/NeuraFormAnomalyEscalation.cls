/**
 * Threshold-based anomaly escalation (Vignette 3).
 *
 * Invoked from a record-triggered Flow when a Form_Finding__c is created. It
 * looks across a location's recent inspections and, when the same finding has
 * recurred enough times to be a pattern (not a one-off), opens an
 * Anomaly_Alert__c with an AI-drafted, brand-facing message - so Ops can reach
 * out to the brand proactively, before the customer escalates.
 *
 * The detection + LLM draft run in a Queueable (async) because the invocable
 * fires inside the Flow's triggering DML transaction, where callouts to the
 * Models API are not permitted. Enqueuing moves the callout to its own
 * transaction. A bulk finding insert can carry many distinct accounts, and
 * each new alert costs one LLM callout — accounts are processed in chunks of
 * MAX_ACCOUNTS_PER_JOB per queueable execution, chaining for the remainder.
 */
public with sharing class NeuraFormAnomalyEscalation {

    // Number of recent visits the same finding must appear in to escalate.
    @TestVisible private static Integer THRESHOLD = 3;
    @TestVisible private static Integer VISIT_WINDOW = 6;
    // Callout + SOQL budget guard: each account costs at most 1 LLM callout,
    // so a chunk stays far inside the 100-callout / 100-SOQL limits.
    @TestVisible private static Integer MAX_ACCOUNTS_PER_JOB = 10;

    // Test hooks.
    @TestVisible private static String mockLLMResponse = null;
    @TestVisible private static Boolean runSynchronouslyForTest = false;

    public class Request {
        @InvocableVariable(required=true label='Inspection (Linked Form) Id')
        public Id linkedFormId;
    }

    @InvocableMethod(label='Escalate Inspection Anomalies'
        description='Detects recurring findings at a location and drafts a brand-facing alert.')
    public static void escalate(List<Request> requests) {
        Set<Id> linkedFormIds = new Set<Id>();
        for (Request r : requests) {
            if (r != null && r.linkedFormId != null) linkedFormIds.add(r.linkedFormId);
        }
        if (linkedFormIds.isEmpty()) return;

        if (runSynchronouslyForTest) {
            process(linkedFormIds);
            return;
        }
        // One child enqueue IS allowed from a queueable context (e.g. when a
        // finding is created by the scoring rollup job), so don't gate on
        // System.isQueueable() — only on the remaining queueable budget.
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new AnomalyJob(linkedFormIds));
        } else {
            // Out of queueable budget: surface the skip instead of silently
            // dropping the scan. The pattern re-triggers on the next finding
            // at the same location, so a miss here is recoverable.
            System.debug(LoggingLevel.WARN,
                'NeuraFormAnomalyEscalation: queueable budget exhausted; skipped anomaly scan for ' +
                linkedFormIds);
        }
    }

    public class AnomalyJob implements Queueable, Database.AllowsCallouts {
        private Set<Id> linkedFormIds;
        public AnomalyJob(Set<Id> ids) { this.linkedFormIds = ids; }
        public void execute(QueueableContext ctx) {
            process(linkedFormIds);
        }
    }

    @TestVisible
    private static void process(Set<Id> linkedFormIds) {
        // Resolve the locations involved (dedupe so two findings on the same
        // visit don't create two alerts).
        Map<Id, Linked_Form__c> forms = new Map<Id, Linked_Form__c>([
            SELECT Id, Account__c, Form_Template__c
            FROM Linked_Form__c
            WHERE Id IN :linkedFormIds AND Account__c != null
        ]);
        if (forms.isEmpty()) return;

        // One representative form per account, chunked for the callout budget.
        Map<Id, Linked_Form__c> formByAccount = new Map<Id, Linked_Form__c>();
        Set<Id> deferredFormIds = new Set<Id>();
        for (Linked_Form__c lf : forms.values()) {
            if (formByAccount.containsKey(lf.Account__c)) continue;
            if (formByAccount.size() >= MAX_ACCOUNTS_PER_JOB) {
                deferredFormIds.add(lf.Id);
                continue;
            }
            formByAccount.put(lf.Account__c, lf);
        }

        Set<Id> accountIds = formByAccount.keySet();
        Set<Id> templateIds = new Set<Id>();
        for (Linked_Form__c lf : formByAccount.values()) templateIds.add(lf.Form_Template__c);

        // Bulk pre-queries (one SOQL each), replacing the former per-account
        // queries inside the loop which hit governor limits on bulk inserts.
        //
        // Visit window per (account, template): completed visits, plus the
        // triggering visits themselves (they may still be In Progress while
        // the inspector is on site).
        Map<String, List<Id>> visitsByPair = new Map<String, List<Id>>();
        Map<Id, String> pairForVisit = new Map<Id, String>();
        for (Linked_Form__c v : [
            SELECT Id, Account__c, Form_Template__c
            FROM Linked_Form__c
            WHERE Account__c IN :accountIds
              AND Form_Template__c IN :templateIds
              AND (Status__c = 'Completed' OR Id IN :linkedFormIds)
            ORDER BY Visit_Date__c DESC NULLS LAST
        ]) {
            String pair = v.Account__c + ':' + v.Form_Template__c;
            List<Id> bucket = visitsByPair.get(pair);
            if (bucket == null) { bucket = new List<Id>(); visitsByPair.put(pair, bucket); }
            if (bucket.size() >= VISIT_WINDOW) continue;
            bucket.add(v.Id);
            pairForVisit.put(v.Id, pair);
        }

        List<Form_Finding__c> findings = pairForVisit.isEmpty()
            ? new List<Form_Finding__c>()
            : [
                SELECT Notes__c, Severity__c, Linked_Form__c
                FROM Form_Finding__c
                WHERE Linked_Form__c IN :pairForVisit.keySet()
            ];

        // Open alerts per account, for dedupe.
        Set<String> openAlertKeys = new Set<String>();
        for (Anomaly_Alert__c a : [
            SELECT Account__c, Pattern_Summary__c
            FROM Anomaly_Alert__c
            WHERE Account__c IN :accountIds
              AND Status__c IN ('New', 'Reviewed')
        ]) {
            openAlertKeys.add(a.Account__c + ':' + a.Pattern_Summary__c);
        }

        Map<Id, Account> accountsById = new Map<Id, Account>([
            SELECT Name FROM Account WHERE Id IN :accountIds
        ]);

        // Brand contact = first contact on the alert's own Account. (Replaces
        // a hardcoded demo-person lookup; orgs that want a specific routing
        // contact can model it on the Account and refine here.)
        Map<Id, Contact> contactByAccount = new Map<Id, Contact>();
        for (Contact c : [
            SELECT Id, FirstName, AccountId
            FROM Contact
            WHERE AccountId IN :accountIds
            ORDER BY CreatedDate ASC
        ]) {
            if (!contactByAccount.containsKey(c.AccountId)) {
                contactByAccount.put(c.AccountId, c);
            }
        }

        List<Anomaly_Alert__c> toInsert = new List<Anomaly_Alert__c>();
        for (Linked_Form__c lf : formByAccount.values()) {
            String pair = lf.Account__c + ':' + lf.Form_Template__c;
            List<Id> visitIds = visitsByPair.get(pair);
            if (visitIds == null || visitIds.isEmpty()) continue;
            Set<Id> visitIdSet = new Set<Id>(visitIds);

            // Recurrence = DISTINCT visits a normalized note appears in, not
            // raw finding rows — two identical findings on one visit are one
            // occurrence, matching the "recurred across N visits" contract.
            Map<String, Set<Id>> visitsByNote = new Map<String, Set<Id>>();
            Map<String, String> labelFor = new Map<String, String>();
            for (Form_Finding__c f : findings) {
                if (!visitIdSet.contains(f.Linked_Form__c)) continue;
                if (String.isBlank(f.Notes__c)) continue;
                String key = f.Notes__c.trim().toLowerCase();
                Set<Id> noteVisits = visitsByNote.get(key);
                if (noteVisits == null) { noteVisits = new Set<Id>(); visitsByNote.put(key, noteVisits); }
                noteVisits.add(f.Linked_Form__c);
                if (!labelFor.containsKey(key)) labelFor.put(key, f.Notes__c.trim());
            }
            String topKey = null; Integer topCount = 0;
            for (String k : visitsByNote.keySet()) {
                Integer n = visitsByNote.get(k).size();
                if (n > topCount) { topCount = n; topKey = k; }
            }
            if (topKey == null || topCount < THRESHOLD) continue;

            String pattern = labelFor.get(topKey);
            if (pattern != null && pattern.length() > 255) pattern = pattern.substring(0, 255);

            // Don't pile up duplicate open alerts for the same location+pattern.
            // This in-transaction check skips the LLM draft for known dupes;
            // the unique Dedupe_Key__c below is what actually closes the race
            // when two queueables pass this check concurrently.
            if (openAlertKeys.contains(lf.Account__c + ':' + pattern)) continue;
            openAlertKeys.add(lf.Account__c + ':' + pattern);

            Account acct = accountsById.get(lf.Account__c);
            String accountName = acct != null ? acct.Name : 'this location';
            Contact brandContact = contactByAccount.get(lf.Account__c);

            toInsert.add(new Anomaly_Alert__c(
                Account__c = lf.Account__c,
                Linked_Form__c = lf.Id,
                Pattern_Summary__c = pattern,
                Recurrence_Count__c = topCount,
                Status__c = 'New',
                Dedupe_Key__c = dedupeKey(lf.Account__c, topKey),
                Brand_Contact__c = brandContact != null ? brandContact.Id : null,
                Draft_Message__c = draftMessage(accountName, pattern, topCount,
                    brandContact != null ? brandContact.FirstName : null)
            ));
        }

        if (!toInsert.isEmpty()) {
            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.CREATABLE, toInsert
            );
            // Partial-allowed: a DUPLICATE_VALUE failure on Dedupe_Key__c is
            // the race loser discovering another queueable already opened
            // this alert — expected, not an error. Anything else is logged.
            Database.SaveResult[] results = Database.insert(decision.getRecords(), false);
            for (Database.SaveResult r : results) {
                if (r.isSuccess()) continue;
                for (Database.Error err : r.getErrors()) {
                    if (err.getStatusCode() != StatusCode.DUPLICATE_VALUE) {
                        System.debug(LoggingLevel.ERROR,
                            'Anomaly alert insert failed: ' + err.getMessage());
                    }
                }
            }
        }

        // Accounts beyond this job's chunk: chain one follow-up queueable.
        if (!deferredFormIds.isEmpty()
            && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new AnomalyJob(deferredFormIds));
        }
    }

    /** Account Id + SHA-256 of the normalized pattern — the value behind the
     *  unique Dedupe_Key__c index. Hashed so a 255-char note can't overflow
     *  the key, normalized so casing/whitespace variants collide on purpose. */
    @TestVisible
    private static String dedupeKey(Id accountId, String normalizedPattern) {
        String digest = EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', Blob.valueOf(normalizedPattern))
        );
        return accountId + ':' + digest;
    }

    @TestVisible
    private static String draftMessage(String location, String pattern, Integer count, String contactFirstName) {
        String greeting = String.isNotBlank(contactFirstName) ? contactFirstName : 'team';
        String systemPrompt =
            'You draft short, professional, proactive customer communications for a ' +
            'commercial inspection company reaching out to a brand partner. Tone: ' +
            'confident, helpful, not alarmist. 1 short paragraph plus a one-line next ' +
            'step. No subject line, no markdown.';
        String userPrompt =
            'Draft a note to ' + greeting + ', the brand quality contact. Our inspectors ' +
            'have flagged a recurring issue at ' + location + ': "' + pattern + '" on ' +
            count + ' of the last several visits. We are addressing it and want to flag it ' +
            'proactively before it affects operations. Offer to share the visit history.';
        // Respect the org's AI opt-in even on this async path — the flow fires
        // regardless of the flag, so the gate has to live here.
        String llm = NeuraFormLLMService.isEnabled()
            ? invokeLLM(systemPrompt, userPrompt)
            : null;
        if (String.isNotBlank(llm)) return llm;
        // Deterministic fallback so an alert always has a usable draft.
        return 'Hi ' + greeting + ',\n\nDuring our recent inspections at ' + location +
            ', our team has flagged a recurring issue — "' + pattern + '" — on ' + count +
            ' of the last several visits. We are already acting on it and wanted to bring ' +
            'it to your attention proactively. Happy to walk you through the visit history.\n\n' +
            'Best regards,\nThe Operations Team';
    }

    @TestVisible
    private static String invokeLLM(String systemPrompt, String userPrompt) {
        if (mockLLMResponse != null) return mockLLMResponse;
        return NeuraFormLLMService.chat(systemPrompt, userPrompt);
    }
}
