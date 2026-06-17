/**
 * Single-payload read model for the Linked_Form "one-stop" summary LWC
 * (neuraFormSummary). Rolls up the inspection header, score, findings, and
 * related anomaly alerts so an Ops/admin user sees everything for one form
 * without clicking into child records. The child objects still exist for
 * list-view / report-by-child use cases — this is purely a convenience view.
 *
 * with sharing: the summary must honor the running user's record access
 * (internal Ops today; safe if ever surfaced elsewhere).
 */
public with sharing class NeuraFormSummaryController {

    /** Display rank for severities so findings sort worst-first in Apex. */
    private static final Map<String, Integer> SEV_RANK = new Map<String, Integer>{
        'Critical' => 0, 'High' => 1, 'Medium' => 2, 'Low' => 3
    };

    // FLS gates for fields the portal permset deliberately hides. The SOQL runs
    // in system mode (so it never errors), but we only surface these in the DTO
    // when the running user can actually read them — internal Ops sees them,
    // portal customers get null and the LWC's if:true guards hide the UI.
    private static final Boolean CAN_SEE_REROLL =
        Schema.sObjectType.Linked_Form__c.fields.Re_Roll__c.isAccessible();
    private static final Boolean CAN_SEE_ANOMALY_STATUS =
        Schema.sObjectType.Anomaly_Alert__c.fields.Status__c.isAccessible();
    private static final Boolean CAN_SEE_ANOMALY_DRAFT =
        Schema.sObjectType.Anomaly_Alert__c.fields.Draft_Message__c.isAccessible();
    private static final Boolean CAN_SEE_ANOMALY_CONTACT =
        Schema.sObjectType.Anomaly_Alert__c.fields.Brand_Contact__c.isAccessible();

    @AuraEnabled(cacheable=true)
    public static Summary getSummary(Id linkedFormId) {
        if (linkedFormId == null) {
            throw new AuraHandledException('No record id supplied.');
        }

        List<Linked_Form__c> lfs = [
            SELECT Id, Name, Status__c, Score__c, Max_Score__c, Score_Percent__c,
                Findings_Open_Count__c, Findings_Blocking_Count__c,
                Account__c, Account__r.Name,
                Form_Template__r.Name, Form_Template__r.Pass_Threshold_Percent__c,
                Form_Template__r.Scoring_Enabled__c,
                Visit_Date__c, Started_At__c, Completed_At__c,
                Completed_By__r.Name, Fill_Duration_Minutes__c, Re_Roll__c,
                Signed_By_Name__c, Signature_Captured_At__c, Service_Summary__c,
                Work_Order__r.WorkOrderNumber
            FROM Linked_Form__c
            WHERE Id = :linkedFormId
            LIMIT 1
        ];
        if (lfs.isEmpty()) {
            throw new AuraHandledException('Inspection not found or not accessible.');
        }
        Linked_Form__c lf = lfs[0];

        Summary s = new Summary();
        s.id = lf.Id;
        s.name = lf.Name;
        s.status = lf.Status__c;
        s.templateName = lf.Form_Template__r != null ? lf.Form_Template__r.Name : null;
        s.accountName = lf.Account__r != null ? lf.Account__r.Name : null;
        s.workOrderNumber = lf.Work_Order__r != null ? lf.Work_Order__r.WorkOrderNumber : null;
        s.visitDate = lf.Visit_Date__c;
        s.startedAt = lf.Started_At__c;
        s.completedAt = lf.Completed_At__c;
        s.inspector = lf.Completed_By__r != null ? lf.Completed_By__r.Name : null;
        s.durationMinutes = lf.Fill_Duration_Minutes__c;
        // Re-roll is internal-only (the portal permset hides it). Gate on FLS so
        // the same component is safe on a customer portal page.
        s.reRoll = CAN_SEE_REROLL && lf.Re_Roll__c == true;
        s.signedByName = lf.Signed_By_Name__c;
        s.signatureCapturedAt = lf.Signature_Captured_At__c;
        s.serviceSummary = lf.Service_Summary__c;

        // Score block. The LWC's score badge computes percent + pass/fail from
        // score + max + threshold, so we hand it raw numbers (not the
        // double-scaled formula) plus the template threshold.
        s.scoringEnabled = lf.Form_Template__r != null
            && lf.Form_Template__r.Scoring_Enabled__c == true;
        s.score = lf.Score__c;
        s.maxScore = lf.Max_Score__c;
        s.passThreshold = lf.Form_Template__r != null
            ? lf.Form_Template__r.Pass_Threshold_Percent__c : null;
        s.openFindings = lf.Findings_Open_Count__c == null ? 0 : (Integer) lf.Findings_Open_Count__c;
        s.blockingFindings = lf.Findings_Blocking_Count__c == null ? 0 : (Integer) lf.Findings_Blocking_Count__c;

        // Findings — worst-severity-first, blocking ahead of non-blocking.
        s.findings = new List<FindingRow>();
        Map<String, Integer> sevCounts = new Map<String, Integer>{
            'Critical' => 0, 'High' => 0, 'Medium' => 0, 'Low' => 0
        };
        List<Form_Finding__c> findingRecs = [
            SELECT Id, Name, Severity__c, Status__c, Notes__c, Due_Date__c,
                Photo_Required__c, Photo_Attached__c, Blocks_Submission__c,
                Form_Answer__c, Form_Question_Catalog__r.Question__c
            FROM Form_Finding__c
            WHERE Linked_Form__c = :linkedFormId
        ];

        // Photos are attached to the finding's Form_Answer__c (the inspector's
        // photo capture), linked via ContentDocumentLink. Bulk-resolve the
        // newest image file per answer so each finding can surface a thumbnail.
        Set<Id> answerIds = new Set<Id>();
        for (Form_Finding__c f : findingRecs) {
            if (f.Form_Answer__c != null) answerIds.add(f.Form_Answer__c);
        }
        Map<Id, ContentDocumentLink> photoByAnswer = new Map<Id, ContentDocumentLink>();
        if (!answerIds.isEmpty()) {
            for (ContentDocumentLink cdl : [
                SELECT LinkedEntityId, ContentDocumentId,
                    ContentDocument.Title, ContentDocument.FileType,
                    ContentDocument.LatestPublishedVersionId
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :answerIds
            ]) {
                String ft = cdl.ContentDocument != null ? cdl.ContentDocument.FileType : null;
                Boolean isImage = ft != null
                    && new Set<String>{'PNG','JPG','JPEG','GIF','WEBP','HEIC'}.contains(ft.toUpperCase());
                // First image wins (one capture per question is the norm).
                if (isImage && !photoByAnswer.containsKey(cdl.LinkedEntityId)) {
                    photoByAnswer.put(cdl.LinkedEntityId, cdl);
                }
            }
        }

        for (Form_Finding__c f : findingRecs) {
            FindingRow r = new FindingRow();
            r.id = f.Id;
            r.name = f.Name;
            r.severity = f.Severity__c;
            r.status = f.Status__c;
            r.notes = f.Notes__c;
            r.dueDate = f.Due_Date__c;
            r.photoRequired = f.Photo_Required__c == true;
            r.photoAttached = f.Photo_Attached__c == true;
            r.blocksSubmission = f.Blocks_Submission__c == true;
            r.question = f.Form_Question_Catalog__r != null
                ? f.Form_Question_Catalog__r.Question__c : null;
            ContentDocumentLink photo = f.Form_Answer__c != null
                ? photoByAnswer.get(f.Form_Answer__c) : null;
            if (photo != null && photo.ContentDocument != null) {
                r.photoVersionId = photo.ContentDocument.LatestPublishedVersionId;
                r.photoDocumentId = photo.ContentDocumentId;
                r.photoTitle = photo.ContentDocument.Title;
            }
            r.sevRank = SEV_RANK.containsKey(f.Severity__c) ? SEV_RANK.get(f.Severity__c) : 9;
            s.findings.add(r);
            if (sevCounts.containsKey(f.Severity__c)) {
                sevCounts.put(f.Severity__c, sevCounts.get(f.Severity__c) + 1);
            }
        }
        s.findings.sort();
        s.totalFindings = findingRecs.size();
        s.criticalCount = sevCounts.get('Critical');
        s.highCount = sevCounts.get('High');
        s.mediumCount = sevCounts.get('Medium');
        s.lowCount = sevCounts.get('Low');

        // Anomalies linked to this form.
        s.anomalies = new List<AnomalyRow>();
        for (Anomaly_Alert__c a : [
            SELECT Id, Name, Pattern_Summary__c, Recurrence_Count__c, Status__c,
                Brand_Contact__r.Name, Draft_Message__c
            FROM Anomaly_Alert__c
            WHERE Linked_Form__c = :linkedFormId
            ORDER BY Recurrence_Count__c DESC NULLS LAST
        ]) {
            AnomalyRow r = new AnomalyRow();
            r.id = a.Id;
            r.name = a.Name;
            r.patternSummary = a.Pattern_Summary__c;
            r.recurrenceCount = a.Recurrence_Count__c == null ? 0 : (Integer) a.Recurrence_Count__c;
            // Internal-only fields — hidden from portal customers via FLS gate.
            r.status = CAN_SEE_ANOMALY_STATUS ? a.Status__c : null;
            r.draftMessage = CAN_SEE_ANOMALY_DRAFT ? a.Draft_Message__c : null;
            r.brandContact = (CAN_SEE_ANOMALY_CONTACT && a.Brand_Contact__r != null)
                ? a.Brand_Contact__r.Name : null;
            s.anomalies.add(r);
        }
        s.totalAnomalies = s.anomalies.size();

        return s;
    }

    /**
     * Manually resolve a finding from the summary card (internal Ops action).
     * NOT cacheable (it writes). Uses `update as user` so the running user's
     * field/object/sharing access is enforced — a read-only portal user
     * physically cannot resolve, even if the UI button were ever exposed.
     * Returns the new status for optimistic UI; the LWC also refreshes the wire.
     */
    @AuraEnabled
    public static String resolveFinding(Id findingId) {
        if (findingId == null) {
            throw new AuraHandledException('No finding id supplied.');
        }
        try {
            Form_Finding__c f = new Form_Finding__c(Id = findingId, Status__c = 'Resolved');
            update as user f;
            return 'Resolved';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ---------------------------------------------------------------- wrappers

    public class Summary {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String templateName;
        @AuraEnabled public String accountName;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public Date visitDate;
        @AuraEnabled public Datetime startedAt;
        @AuraEnabled public Datetime completedAt;
        @AuraEnabled public String inspector;
        @AuraEnabled public Decimal durationMinutes;
        @AuraEnabled public Boolean reRoll;
        @AuraEnabled public String signedByName;
        @AuraEnabled public Datetime signatureCapturedAt;
        @AuraEnabled public String serviceSummary;

        @AuraEnabled public Boolean scoringEnabled;
        @AuraEnabled public Decimal score;
        @AuraEnabled public Decimal maxScore;
        @AuraEnabled public Decimal passThreshold;
        @AuraEnabled public Integer openFindings;
        @AuraEnabled public Integer blockingFindings;

        @AuraEnabled public Integer totalFindings;
        @AuraEnabled public Integer criticalCount;
        @AuraEnabled public Integer highCount;
        @AuraEnabled public Integer mediumCount;
        @AuraEnabled public Integer lowCount;
        @AuraEnabled public List<FindingRow> findings;

        @AuraEnabled public Integer totalAnomalies;
        @AuraEnabled public List<AnomalyRow> anomalies;
    }

    public class FindingRow implements Comparable {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String severity;
        @AuraEnabled public String status;
        @AuraEnabled public String question;
        @AuraEnabled public String notes;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public Boolean photoRequired;
        @AuraEnabled public Boolean photoAttached;
        @AuraEnabled public Boolean blocksSubmission;
        @AuraEnabled public Id photoVersionId;
        @AuraEnabled public Id photoDocumentId;
        @AuraEnabled public String photoTitle;
        public Integer sevRank;

        // Blocking first, then worst severity, so the panel reads top-down.
        public Integer compareTo(Object other) {
            FindingRow o = (FindingRow) other;
            if (this.blocksSubmission != o.blocksSubmission) {
                return this.blocksSubmission ? -1 : 1;
            }
            return this.sevRank - o.sevRank;
        }
    }

    public class AnomalyRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String patternSummary;
        @AuraEnabled public Integer recurrenceCount;
        @AuraEnabled public String status;
        @AuraEnabled public String brandContact;
        @AuraEnabled public String draftMessage;
    }
}
