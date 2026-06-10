/**
 * Tests for NeuraFormAnomalyEscalation. escalate() enqueues the real
 * AnomalyJob queueable, drained synchronously by Test.stopTest(), so the
 * async path is what's under test. The LLM draft is bypassed via the
 * mockLLMResponse hook.
 */
@isTest
private class NeuraFormAnomalyEscalationTest {

    private static Id seedLocation(Integer findingCount, String note) {
        Form_Template__c tpl = new Form_Template__c(Name = 'Anomaly Test Template');
        insert tpl;
        Account acc = new Account(Name = 'Test Store #99');
        insert acc;

        List<Linked_Form__c> visits = new List<Linked_Form__c>();
        for (Integer i = 0; i < findingCount; i++) {
            visits.add(new Linked_Form__c(
                Form_Template__c = tpl.Id, Account__c = acc.Id, Status__c = 'Completed',
                Visit_Date__c = Date.today().addDays(-7 * (findingCount - i))
            ));
        }
        insert visits;

        List<Form_Finding__c> findings = new List<Form_Finding__c>();
        for (Linked_Form__c v : visits) {
            findings.add(new Form_Finding__c(
                Linked_Form__c = v.Id, Severity__c = 'Medium', Status__c = 'Open', Notes__c = note
            ));
        }
        insert findings;

        return visits.isEmpty() ? null : visits[visits.size() - 1].Id;
    }

    private static NeuraFormAnomalyEscalation.Request req(Id linkedFormId) {
        NeuraFormAnomalyEscalation.Request r = new NeuraFormAnomalyEscalation.Request();
        r.linkedFormId = linkedFormId;
        return r;
    }

    @isTest
    static void escalatesWhenThresholdMet() {
        NeuraFormAnomalyEscalation.mockLLMResponse =
            'Hi Jen, we noticed a recurring issue and are on it.';
        Id triggering = seedLocation(3, 'Condensation observed on upper freezer hinge.');

        Test.startTest();
        NeuraFormAnomalyEscalation.escalate(new List<NeuraFormAnomalyEscalation.Request>{ req(triggering) });
        Test.stopTest();

        List<Anomaly_Alert__c> alerts = [
            SELECT Pattern_Summary__c, Recurrence_Count__c, Status__c, Draft_Message__c
            FROM Anomaly_Alert__c
        ];
        System.assertEquals(1, alerts.size(), 'One alert should be opened at threshold.');
        System.assertEquals(3, alerts[0].Recurrence_Count__c);
        System.assertEquals('New', alerts[0].Status__c);
        System.assertEquals('Condensation observed on upper freezer hinge.', alerts[0].Pattern_Summary__c);
        System.assert(String.isNotBlank(alerts[0].Draft_Message__c), 'Draft message should be populated.');
    }

    @isTest
    static void noEscalationBelowThreshold() {
        NeuraFormAnomalyEscalation.mockLLMResponse = 'unused';
        Id triggering = seedLocation(2, 'One-off-ish issue.');

        Test.startTest();
        NeuraFormAnomalyEscalation.escalate(new List<NeuraFormAnomalyEscalation.Request>{ req(triggering) });
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Anomaly_Alert__c], 'Below threshold: no alert.');
    }

    @isTest
    static void noDuplicateAlertForSamePattern() {
        NeuraFormAnomalyEscalation.mockLLMResponse = 'draft';
        Id triggering = seedLocation(3, 'Condensation observed on upper freezer hinge.');

        Test.startTest();
        NeuraFormAnomalyEscalation.escalate(new List<NeuraFormAnomalyEscalation.Request>{ req(triggering) });
        NeuraFormAnomalyEscalation.escalate(new List<NeuraFormAnomalyEscalation.Request>{ req(triggering) });
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Anomaly_Alert__c],
            'A second run with the same open pattern should not duplicate.');
    }

    @isTest
    static void fallbackDraftWhenNoLLM() {
        // No mock set and AI not enabled -> deterministic fallback draft,
        // with no Models API callout attempted (the gate must hold on this
        // async path even though the flow fires regardless of the flag).
        String draft = NeuraFormAnomalyEscalation.draftMessage(
            'Burger King #4421', 'Condensation on upper freezer hinge', 3, 'Jen'
        );
        System.assert(draft.contains('Burger King #4421'));
        System.assert(draft.contains('Jen'));
    }

    @isTest
    static void countsDistinctVisitsNotFindings() {
        NeuraFormAnomalyEscalation.mockLLMResponse = 'draft';
        // Two visits, with the SAME note duplicated on one visit: 3 finding
        // rows but only 2 distinct visits — below the threshold of 3.
        Id triggering = seedLocation(2, 'Condensation observed on upper freezer hinge.');
        List<Linked_Form__c> visits = [SELECT Id FROM Linked_Form__c LIMIT 1];
        insert new Form_Finding__c(
            Linked_Form__c = visits[0].Id, Severity__c = 'Medium', Status__c = 'Open',
            Notes__c = 'Condensation observed on upper freezer hinge.'
        );

        Test.startTest();
        NeuraFormAnomalyEscalation.escalate(new List<NeuraFormAnomalyEscalation.Request>{ req(triggering) });
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Anomaly_Alert__c],
            'Two identical findings on one visit must count as one occurrence.');
    }

    @isTest
    static void resolvesBrandContactFromAccount() {
        NeuraFormAnomalyEscalation.mockLLMResponse = 'draft';
        Id triggering = seedLocation(3, 'Recurring gasket wear.');
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact c = new Contact(FirstName = 'Quinn', LastName = 'Roberts', AccountId = acc.Id);
        insert c;

        Test.startTest();
        NeuraFormAnomalyEscalation.escalate(new List<NeuraFormAnomalyEscalation.Request>{ req(triggering) });
        Test.stopTest();

        List<Anomaly_Alert__c> alerts = [SELECT Brand_Contact__c FROM Anomaly_Alert__c];
        System.assertEquals(1, alerts.size());
        System.assertEquals(c.Id, alerts[0].Brand_Contact__c,
            'Brand contact should resolve from the alert Account, not a hardcoded person.');
    }

    @isTest
    static void dedupeKeyBlocksConcurrentDuplicateAtDatabase() {
        NeuraFormAnomalyEscalation.mockLLMResponse = 'draft';
        Id triggering = seedLocation(3, 'Condensation observed on upper freezer hinge.');

        Test.startTest();
        NeuraFormAnomalyEscalation.escalate(new List<NeuraFormAnomalyEscalation.Request>{ req(triggering) });
        Test.stopTest();

        Anomaly_Alert__c alert = [SELECT Account__c, Dedupe_Key__c FROM Anomaly_Alert__c LIMIT 1];
        System.assert(String.isNotBlank(alert.Dedupe_Key__c), 'Alerts must carry the dedupe key.');
        System.assert(alert.Dedupe_Key__c.startsWith(alert.Account__c + ':'));

        // Simulate the race loser: a second insert with the same key (as a
        // concurrent queueable would produce) must be rejected by the unique
        // index — the application-level check can't see across transactions.
        Database.SaveResult sr = Database.insert(new Anomaly_Alert__c(
            Account__c = alert.Account__c,
            Pattern_Summary__c = 'race twin',
            Status__c = 'New',
            Dedupe_Key__c = alert.Dedupe_Key__c
        ), false);
        System.assertEquals(false, sr.isSuccess(), 'Unique index must reject the duplicate.');
        System.assertEquals(StatusCode.DUPLICATE_VALUE, sr.getErrors()[0].getStatusCode());
    }

    @isTest
    static void closingAnAlertFreesTheDedupeSlot() {
        NeuraFormAnomalyEscalation.mockLLMResponse = 'draft';
        Id triggering = seedLocation(3, 'Recurring drain blockage.');

        Test.startTest();
        NeuraFormAnomalyEscalation.escalate(new List<NeuraFormAnomalyEscalation.Request>{ req(triggering) });
        Test.stopTest();

        Anomaly_Alert__c alert = [SELECT Id, Dedupe_Key__c FROM Anomaly_Alert__c LIMIT 1];
        String openKey = alert.Dedupe_Key__c;
        alert.Status__c = 'Dismissed';
        update alert;

        alert = [SELECT Dedupe_Key__c FROM Anomaly_Alert__c WHERE Id = :alert.Id];
        System.assert(alert.Dedupe_Key__c.endsWith(':' + alert.Id),
            'Closing must suffix the key so the bare key is free again.');

        // The same pattern recurring after dismissal is a legitimate NEW
        // alert — the freed slot must accept it.
        Database.SaveResult sr = Database.insert(new Anomaly_Alert__c(
            Account__c = [SELECT Account__c FROM Anomaly_Alert__c WHERE Id = :alert.Id].Account__c,
            Pattern_Summary__c = 'Recurring drain blockage.',
            Status__c = 'New',
            Dedupe_Key__c = openKey
        ), false);
        System.assertEquals(true, sr.isSuccess(),
            'A dismissed alert must not block future alerts for the same pattern.');
    }

    @isTest
    static void ignoresFormsWithoutAccount() {
        NeuraFormAnomalyEscalation.mockLLMResponse = 'draft';
        Form_Template__c tpl = new Form_Template__c(Name = 'No Account Template');
        insert tpl;
        Linked_Form__c lf = new Linked_Form__c(Form_Template__c = tpl.Id, Status__c = 'Completed');
        insert lf;

        Test.startTest();
        NeuraFormAnomalyEscalation.escalate(new List<NeuraFormAnomalyEscalation.Request>{ req(lf.Id) });
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Anomaly_Alert__c],
            'Forms without an Account cannot be escalated.');
    }
}
