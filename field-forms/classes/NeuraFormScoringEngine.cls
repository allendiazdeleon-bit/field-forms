/**
 * Runtime engine for Pillar 5 scoring + findings on Form_Answer__c.
 *
 * Called from FormAnswerScoringTrigger (after insert / after update). Stays
 * out of NeuraFormLogic so the orchestrator's parallel work on that class
 * doesn't collide — this is a pure additive helper that the trigger
 * delegates to. Mirrors NeuraFormLogic's transaction-local recursion guard
 * pattern (snapshotEnqueued / pendingSnapshotIds).
 *
 * Flow per fired trigger:
 *   1. Bail out cheaply if FieldForms_Configuration__c.Scoring_Enabled__c
 *      is false. The trigger fires on every answer save; this short-circuit
 *      is the most important perf line in the whole pillar.
 *   2. Load each answer's binding -&gt; catalog -&gt; template and filter to
 *      templates with Scoring_Enabled__c = true.
 *   3. Bucket by Linked_Form__c. Build a per-form sibling answer map so the
 *      scoring evaluator can resolve resource = "external-ref" lookups.
 *   4. Evaluate Pass_Criteria__c per answer, prep Form_Answer__c updates
 *      (Passed__c + Points_Earned__c).
 *   5. Upsert findings on failures, auto-resolve findings on passes.
 *   6. Recalculate per-Linked_Form rollups (Score__c, Max_Score__c,
 *      Findings_Open_Count__c, Findings_Blocking_Count__c) by aggregating
 *      across the entire response.
 *
 * Bulk-safety: above BULK_THRESHOLD answers in a single firing the engine
 * enqueues NeuraFormScoringRollupQueueable rather than running inline,
 * matching the NeuraFormSnapshotQueueable bifurcation. Recursion is
 * suppressed via the isProcessing flag so the Form_Answer__c update in
 * step 4 doesn't refire the trigger into another scoring pass.
 */
public with sharing class NeuraFormScoringEngine {

    /** Bulk threshold above which the engine defers to the queueable. */
    @TestVisible private static Integer BULK_THRESHOLD = 50;

    /**
     * Recursion suppressor. True while a call to handle()/process() is on
     * the call stack — nested triggers fired by our own DMLs see this and
     * return immediately. The flag is cleared in a finally block so a
     * subsequent top-level DML in the same transaction still processes
     * normally (the user updating an answer twice in one test, for
     * instance).
     */
    @TestVisible private static Boolean isProcessing = false;

    /** Per-transaction once-only guard for the queueable bifurcation. */
    @TestVisible private static Boolean rollupEnqueued = false;

    // ------------------------------------------------------------------ entry

    /**
     * Trigger entry point. Runs synchronously for small scopes; enqueues a
     * queueable above BULK_THRESHOLD. Callers pass the trigger's new list
     * (insert) or new list (update — old values aren't needed by the
     * scoring pipeline, but the queueable threshold is sized off it).
     */
    public static void handle(List<Form_Answer__c> answers) {
        if (answers == null || answers.isEmpty()) return;
        if (!isOrgScoringEnabled()) return;
        // Nested-trigger guard: when our own DMLs refire the trigger,
        // isProcessing is already true and we return without re-entering.
        if (isProcessing) return;

        // Strip rows without ids (defensive — after-insert always has ids).
        List<Form_Answer__c> scope = new List<Form_Answer__c>();
        for (Form_Answer__c a : answers) {
            if (a.Id == null) continue;
            scope.add(a);
        }
        if (scope.isEmpty()) return;

        if (scope.size() > BULK_THRESHOLD
            && !System.isQueueable()
            && !System.isBatch()
            && !System.isFuture()) {
            enqueueRollup(scope);
            return;
        }

        process(scope);
    }

    /**
     * Synchronous processor. Public so the queueable can re-enter it.
     * Toggles the isProcessing recursion guard around its body so any DML
     * fired here doesn't re-enter handle() / process() for the same scope.
     */
    public static void process(List<Form_Answer__c> seedAnswers) {
        if (seedAnswers == null || seedAnswers.isEmpty()) return;
        if (isProcessing) return;

        isProcessing = true;
        try {
            processInternal(seedAnswers);
        } finally {
            isProcessing = false;
        }
    }

    private static void processInternal(List<Form_Answer__c> seedAnswers) {
        // Collect Linked_Form scopes — every rollup needs the full answer
        // set for the parent response, not just the changed rows.
        Set<Id> linkedFormIds = new Set<Id>();
        Set<Id> seedIds = new Set<Id>();
        for (Form_Answer__c a : seedAnswers) {
            if (a.Linked_Form__c != null) linkedFormIds.add(a.Linked_Form__c);
            if (a.Id != null) seedIds.add(a.Id);
        }
        if (linkedFormIds.isEmpty()) return;

        // Pull every answer for those Linked_Forms with the binding /
        // catalog / template fields needed to score. Avoids the per-answer
        // SOQL pattern flagged in phase-1-findings.md.
        List<Form_Answer__c> fullScope = [
            SELECT Id, Answer__c, Linked_Form__c, Passed__c, Points_Earned__c,
                Form_Question__c,
                Form_Question__r.External_Reference__c,
                Form_Question__r.Form_Question_Catalog__c,
                Form_Question__r.Form_Question_Catalog__r.External_Reference__c,
                Form_Question__r.Form_Question_Catalog__r.Pass_Criteria__c,
                Form_Question__r.Form_Question_Catalog__r.Weight__c,
                Form_Question__r.Form_Question_Catalog__r.Failure_Auto_Finding__c,
                Form_Question__r.Form_Question_Catalog__r.Failure_Photo_Required__c,
                Form_Question__r.Form_Question_Catalog__r.Failure_Severity__c,
                Linked_Form__r.Form_Template__c,
                Linked_Form__r.Form_Template__r.Scoring_Enabled__c,
                Linked_Form__r.Form_Template__r.Max_Score__c
            FROM Form_Answer__c
            WHERE Linked_Form__c IN :linkedFormIds
        ];

        // Bucket per response so a single Linked_Form's answers are
        // evaluated as one pass (the sibling-answer map needs the full
        // set in scope).
        Map<Id, List<Form_Answer__c>> byForm = new Map<Id, List<Form_Answer__c>>();
        for (Form_Answer__c a : fullScope) {
            List<Form_Answer__c> bucket = byForm.get(a.Linked_Form__c);
            if (bucket == null) {
                bucket = new List<Form_Answer__c>();
                byForm.put(a.Linked_Form__c, bucket);
            }
            bucket.add(a);
        }

        List<Form_Answer__c> answerUpdates = new List<Form_Answer__c>();
        List<Form_Finding__c> findingsToUpsert = new List<Form_Finding__c>();

        // Track which (linked_form, answer) pairs should auto-resolve any
        // open finding — answers that now Pass have any existing finding
        // closed out.
        Set<Id> resolveFindingForAnswerIds = new Set<Id>();

        Map<Id, Decimal> formMaxScoreOverride = new Map<Id, Decimal>();

        for (Id formId : byForm.keySet()) {
            List<Form_Answer__c> bucket = byForm.get(formId);

            // Find template scoring flag from any answer (all answers in
            // one Linked_Form share the same template).
            Boolean templateScoringOn = false;
            Decimal templateMaxScore = null;
            for (Form_Answer__c a : bucket) {
                if (a.Linked_Form__r != null
                    && a.Linked_Form__r.Form_Template__r != null) {
                    templateScoringOn = a.Linked_Form__r.Form_Template__r.Scoring_Enabled__c == true;
                    templateMaxScore = a.Linked_Form__r.Form_Template__r.Max_Score__c;
                    break;
                }
            }
            if (templateMaxScore != null) {
                formMaxScoreOverride.put(formId, templateMaxScore);
            }

            if (!templateScoringOn) continue;

            // Sibling answers map keyed by question external_ref (the
            // catalog's external_ref if present, falling back to the
            // binding's).
            Map<String, String> siblings = new Map<String, String>();
            for (Form_Answer__c a : bucket) {
                String ref = catalogExternalRef(a);
                if (ref == null) ref = bindingExternalRef(a);
                if (ref != null) siblings.put(ref, a.Answer__c);
            }

            for (Form_Answer__c a : bucket) {
                String passCriteriaJson = catalogPassCriteria(a);
                Decimal weight = catalogWeight(a);

                // Only mutate answers that were in the trigger's scope this
                // firing. Sibling answers stay as-is — they get re-evaluated
                // next time they're touched. This avoids fanning out an
                // update across the whole response on every keystroke; the
                // isProcessing flag on top of that prevents any single DML
                // we make from re-entering scoring.
                Boolean isSeed = seedIds.contains(a.Id);

                if (String.isBlank(passCriteriaJson)) {
                    if (isSeed && (a.Points_Earned__c != null || a.Passed__c != false)) {
                        a.Points_Earned__c = null;
                        a.Passed__c = false;
                        answerUpdates.add(a);
                    }
                    // Still auto-resolve any stale finding from a prior
                    // criteria configuration.
                    if (isSeed) resolveFindingForAnswerIds.add(a.Id);
                    continue;
                }

                Boolean result = NeuraFormScoringEvaluator.evaluate(
                    passCriteriaJson, a.Answer__c, siblings);

                Boolean newPassed = (result == true);
                Decimal newPoints = (result == null)
                    ? null
                    : (newPassed
                        ? (weight == null ? 1 : weight)
                        : 0);

                Boolean changed = (a.Passed__c != newPassed)
                    || (a.Points_Earned__c != newPoints);
                if (isSeed && changed) {
                    a.Passed__c = newPassed;
                    a.Points_Earned__c = newPoints;
                    answerUpdates.add(a);
                }

                // Findings churn applies to seeds only — same rationale.
                if (isSeed) {
                    if (newPassed) {
                        resolveFindingForAnswerIds.add(a.Id);
                    } else if (result == false && catalogAutoFinding(a)) {
                        findingsToUpsert.add(buildFinding(a, formId));
                    }
                }
                // result == null (un-evaluable) -&gt; do nothing on findings.
            }
        }

        // Apply Form_Answer updates (Passed__c / Points_Earned__c).
        if (!answerUpdates.isEmpty()) {
            // Dedupe — the same record may have been added twice.
            Map<Id, Form_Answer__c> dedupe = new Map<Id, Form_Answer__c>();
            for (Form_Answer__c a : answerUpdates) dedupe.put(a.Id, a);
            update dedupe.values();
        }

        // Auto-resolve open findings whose answer just passed.
        if (!resolveFindingForAnswerIds.isEmpty()) {
            autoResolveFindings(resolveFindingForAnswerIds);
        }

        // Upsert failure findings by External_Reference__c (set to
        // "{formId}:{answerId}" for idempotent re-runs).
        if (!findingsToUpsert.isEmpty()) {
            upsert findingsToUpsert Form_Finding__c.External_Reference__c;
        }

        // Per-form rollup.
        rollupLinkedForms(byForm.keySet(), formMaxScoreOverride);
    }

    // ------------------------------------------------------------- internals

    private static Boolean isOrgScoringEnabled() {
        FieldForms_Configuration__c cfg = FieldForms_Configuration__c.getInstance();
        return cfg != null && cfg.Scoring_Enabled__c == true;
    }

    private static String catalogPassCriteria(Form_Answer__c a) {
        if (a.Form_Question__r == null
            || a.Form_Question__r.Form_Question_Catalog__r == null) return null;
        return a.Form_Question__r.Form_Question_Catalog__r.Pass_Criteria__c;
    }

    private static Decimal catalogWeight(Form_Answer__c a) {
        if (a.Form_Question__r == null
            || a.Form_Question__r.Form_Question_Catalog__r == null) return null;
        return a.Form_Question__r.Form_Question_Catalog__r.Weight__c;
    }

    private static Boolean catalogAutoFinding(Form_Answer__c a) {
        if (a.Form_Question__r == null
            || a.Form_Question__r.Form_Question_Catalog__r == null) return false;
        return a.Form_Question__r.Form_Question_Catalog__r.Failure_Auto_Finding__c == true;
    }

    private static String catalogExternalRef(Form_Answer__c a) {
        if (a.Form_Question__r == null
            || a.Form_Question__r.Form_Question_Catalog__r == null) return null;
        return a.Form_Question__r.Form_Question_Catalog__r.External_Reference__c;
    }

    private static String bindingExternalRef(Form_Answer__c a) {
        if (a.Form_Question__r == null) return null;
        return a.Form_Question__r.External_Reference__c;
    }

    /**
     * Build the Form_Finding__c row for a failing answer. Uses
     * External_Reference__c keyed by "{linkedForm}:{answer}" so the same
     * failure across re-saves upserts onto a single row.
     */
    private static Form_Finding__c buildFinding(Form_Answer__c a, Id formId) {
        Form_Finding__c f = new Form_Finding__c();
        f.Linked_Form__c = formId;
        f.Form_Answer__c = a.Id;
        if (a.Form_Question__r != null) {
            f.Form_Question_Catalog__c = a.Form_Question__r.Form_Question_Catalog__c;
        }
        String sev = 'Low';
        Boolean photoReq = false;
        if (a.Form_Question__r != null
            && a.Form_Question__r.Form_Question_Catalog__r != null) {
            String catSev = a.Form_Question__r.Form_Question_Catalog__r.Failure_Severity__c;
            if (catSev != null) sev = catSev;
            photoReq = a.Form_Question__r.Form_Question_Catalog__r.Failure_Photo_Required__c == true;
        }
        f.Severity__c = sev;
        f.Photo_Required__c = photoReq;
        f.Status__c = 'Open';
        f.External_Reference__c = formId + ':' + a.Id;
        return f;
    }

    /**
     * Transition any Open / In Progress finding tied to the supplied
     * answer Ids to Auto-Resolved. The Status__c change unblocks submit
     * via the Blocks_Submission__c formula.
     */
    private static void autoResolveFindings(Set<Id> answerIds) {
        if (answerIds == null || answerIds.isEmpty()) return;
        List<Form_Finding__c> open = [
            SELECT Id, Status__c
            FROM Form_Finding__c
            WHERE Form_Answer__c IN :answerIds
              AND Status__c IN ('Open', 'In Progress')
        ];
        if (open.isEmpty()) return;
        for (Form_Finding__c f : open) f.Status__c = 'Auto-Resolved';
        update open;
    }

    /**
     * Recompute Score__c, Max_Score__c, Findings_Open_Count__c and
     * Findings_Blocking_Count__c for each form. Pulls all relevant aggregate
     * data with two SOQL calls (one per object) regardless of form count.
     */
    @TestVisible
    private static void rollupLinkedForms(
        Set<Id> formIds,
        Map<Id, Decimal> formMaxScoreOverride
    ) {
        if (formIds == null || formIds.isEmpty()) return;

        Map<Id, Linked_Form__c> updates = new Map<Id, Linked_Form__c>();

        for (AggregateResult ar : [
            SELECT Linked_Form__c form, SUM(Points_Earned__c) total
            FROM Form_Answer__c
            WHERE Linked_Form__c IN :formIds
            GROUP BY Linked_Form__c
        ]) {
            Id formId = (Id) ar.get('form');
            Decimal total = (Decimal) ar.get('total');
            Linked_Form__c lf = updates.get(formId);
            if (lf == null) { lf = new Linked_Form__c(Id = formId); updates.put(formId, lf); }
            lf.Score__c = total;
        }

        Map<Id, Integer> openCounts = new Map<Id, Integer>();
        Map<Id, Integer> blockingCounts = new Map<Id, Integer>();
        for (Form_Finding__c f : [
            SELECT Id, Linked_Form__c, Status__c, Blocks_Submission__c
            FROM Form_Finding__c
            WHERE Linked_Form__c IN :formIds
        ]) {
            Boolean isOpen = (f.Status__c == 'Open' || f.Status__c == 'In Progress');
            if (isOpen) {
                openCounts.put(f.Linked_Form__c,
                    (openCounts.containsKey(f.Linked_Form__c)
                        ? openCounts.get(f.Linked_Form__c)
                        : 0) + 1);
            }
            if (f.Blocks_Submission__c == true) {
                blockingCounts.put(f.Linked_Form__c,
                    (blockingCounts.containsKey(f.Linked_Form__c)
                        ? blockingCounts.get(f.Linked_Form__c)
                        : 0) + 1);
            }
        }

        for (Id formId : formIds) {
            Linked_Form__c lf = updates.get(formId);
            if (lf == null) { lf = new Linked_Form__c(Id = formId); updates.put(formId, lf); }
            lf.Findings_Open_Count__c = openCounts.containsKey(formId) ? openCounts.get(formId) : 0;
            lf.Findings_Blocking_Count__c = blockingCounts.containsKey(formId) ? blockingCounts.get(formId) : 0;
            if (formMaxScoreOverride != null && formMaxScoreOverride.containsKey(formId)) {
                lf.Max_Score__c = formMaxScoreOverride.get(formId);
            }
        }

        if (!updates.isEmpty()) update updates.values();
    }

    /**
     * Defer rollup to the queueable. Keeps the trigger transaction under
     * governor limits when a bulk import / offline-resync writes 100+
     * answers at once. We pass Form_Answer__c ids (not Linked_Form ids)
     * because the queueable re-queries the bindings/templates from each
     * answer; this matches the synchronous path's data flow.
     */
    private static void enqueueRollup(List<Form_Answer__c> scope) {
        Set<Id> answerIds = new Set<Id>();
        for (Form_Answer__c a : scope) answerIds.add(a.Id);
        pendingAnswerIds.addAll(answerIds);
        if (rollupEnqueued) return;
        if (Limits.getLimitQueueableJobs() - Limits.getQueueableJobs() <= 0) {
            // No queueable slot — fall back to inline.
            process(scope);
            return;
        }
        System.enqueueJob(new NeuraFormScoringRollupQueueable(pendingAnswerIds));
        rollupEnqueued = true;
    }

    /** Buffered answer Ids while the queueable is being assembled. */
    @TestVisible private static Set<Id> pendingAnswerIds = new Set<Id>();
}
