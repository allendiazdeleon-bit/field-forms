@isTest
private class NeuraFormSummaryControllerTest {

    @isTest
    static void returnsHeaderScoreFindingsAndAnomalies() {
        Form_Template__c tpl = new Form_Template__c(
            Name = 'Summary Test Template', Scope__c = 'TEST_SCOPE',
            Status__c = 'Active', Scoring_Enabled__c = true,
            Max_Score__c = 70, Pass_Threshold_Percent__c = 80);
        insert tpl;

        Account acc = new Account(Name = 'Summary Test Store');
        insert acc;

        Linked_Form__c lf = new Linked_Form__c(
            Form_Template__c = tpl.Id, Account__c = acc.Id, Status__c = 'Completed',
            Score__c = 60, Max_Score__c = 70, Findings_Open_Count__c = 2,
            Findings_Blocking_Count__c = 1, Signed_By_Name__c = 'Test Manager');
        insert lf;

        insert new List<Form_Finding__c>{
            new Form_Finding__c(Linked_Form__c = lf.Id, Severity__c = 'Critical',
                Status__c = 'Open', Photo_Required__c = true, Photo_Attached__c = false),
            new Form_Finding__c(Linked_Form__c = lf.Id, Severity__c = 'Low',
                Status__c = 'Open', Photo_Required__c = false)
        };

        insert new Anomaly_Alert__c(
            Linked_Form__c = lf.Id, Account__c = acc.Id, Status__c = 'New',
            Pattern_Summary__c = 'Recurring test pattern', Recurrence_Count__c = 3,
            Dedupe_Key__c = 'TEST:' + lf.Id);

        Test.startTest();
        NeuraFormSummaryController.Summary s =
            NeuraFormSummaryController.getSummary(lf.Id);
        Test.stopTest();

        System.assertEquals(lf.Id, s.id, 'wrong record');
        System.assertEquals('Summary Test Template', s.templateName);
        System.assertEquals('Summary Test Store', s.accountName);
        System.assertEquals(true, s.scoringEnabled, 'scoring should be on');
        System.assertEquals(60, s.score);
        System.assertEquals(70, s.maxScore);
        System.assertEquals(80, s.passThreshold);
        System.assertEquals(2, s.totalFindings);
        System.assertEquals(1, s.criticalCount);
        System.assertEquals(1, s.lowCount);
        // Worst-severity-first ordering.
        System.assertEquals('Critical', s.findings[0].severity, 'critical should sort first');
        System.assertEquals(1, s.totalAnomalies);
        System.assertEquals(3, s.anomalies[0].recurrenceCount);
        System.assertEquals('Recurring test pattern', s.anomalies[0].patternSummary);

        // Resolve action flips the finding status.
        Id criticalFindingId = s.findings[0].id;
        String newStatus = NeuraFormSummaryController.resolveFinding(criticalFindingId);
        System.assertEquals('Resolved', newStatus, 'resolve should return new status');
        Form_Finding__c reloaded = [SELECT Status__c FROM Form_Finding__c WHERE Id = :criticalFindingId];
        System.assertEquals('Resolved', reloaded.Status__c, 'finding should persist as Resolved');

        Boolean threw = false;
        try { NeuraFormSummaryController.resolveFinding(null); }
        catch (Exception e) { threw = true; }
        System.assertEquals(true, threw, 'null finding id should throw');
    }

    @isTest
    static void emptyChildrenAndNullIdHandled() {
        Form_Template__c tpl = new Form_Template__c(
            Name = 'Empty Tpl', Status__c = 'Active', Scoring_Enabled__c = false);
        insert tpl;
        Linked_Form__c lf = new Linked_Form__c(Form_Template__c = tpl.Id, Status__c = 'In Progress');
        insert lf;

        Test.startTest();
        NeuraFormSummaryController.Summary s = NeuraFormSummaryController.getSummary(lf.Id);
        System.assertEquals(0, s.totalFindings, 'no findings expected');
        System.assertEquals(0, s.totalAnomalies, 'no anomalies expected');
        System.assertEquals(false, s.scoringEnabled, 'scoring off');

        Boolean threw = false;
        try {
            NeuraFormSummaryController.getSummary(null);
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'null id should throw');
        Test.stopTest();
    }
}
