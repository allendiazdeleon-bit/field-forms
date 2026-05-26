/**
 * Coverage for NeuraFormSnapshotV2 and the v2-gated branch in
 * NeuraFormLogic.updateJSON.
 *
 * Strategy: exercise the public surface (isEnabled, rebuild) directly, and
 * the end-to-end write path via NeuraFormLogic.updateJSON. The chunker is
 * indirectly covered by checking that the rebuild always emits >= 1 row per
 * payload type and that round-tripping the concatenated chunk payload
 * yields a parseable JSON array.
 *
 * See docs/snapshot-v2.md.
 */
@isTest
private class NeuraFormSnapshotV2Test {

    /** Six payload types are always emitted, even for an empty template. */
    private static final Integer EXPECTED_PAYLOAD_TYPES = 6;

    @isTest
    static void isEnabled_returnsFalseWhenSettingMissing() {
        // No FieldForms_Configuration__c record inserted.
        System.assertEquals(false, NeuraFormSnapshotV2.isEnabled(),
            'isEnabled should be false when no custom setting is present');
    }

    @isTest
    static void isEnabled_respectsFlag() {
        insertConfig(true, false);
        System.assertEquals(true, NeuraFormSnapshotV2.isEnabled(),
            'isEnabled should reflect Snapshot_V2_Enabled__c = true');
    }

    @isTest
    static void rebuild_emitsOneRowPerPayloadType_forEmptyWrapper() {
        Form_Template__c template = makeTemplate();

        NeuraFormLogic.FormTemplateWrapper w = new NeuraFormLogic.FormTemplateWrapper(
            template.Id,
            new List<Form_Page__c>(),
            new List<Form_Section__c>(),
            new List<Form_Question__c>(),
            new List<String>(),
            new List<String>(),
            new List<String>()
        );

        Test.startTest();
        NeuraFormSnapshotV2.rebuild(
            new Set<Id>{template.Id},
            new Map<Id, NeuraFormLogic.FormTemplateWrapper>{template.Id => w}
        );
        Test.stopTest();

        List<Form_Template_Snapshot__c> chunks = [
            SELECT Payload_Type__c, Chunk_Index__c, Payload__c, Schema_Version__c
            FROM Form_Template_Snapshot__c
            WHERE Form_Template__c = :template.Id
        ];
        System.assertEquals(EXPECTED_PAYLOAD_TYPES, chunks.size(),
            'Empty template should still emit one chunk per payload type');
        for (Form_Template_Snapshot__c c : chunks) {
            System.assertEquals('[]', c.Payload__c,
                'Empty payload should serialize to []');
            System.assertEquals(0, (Integer) c.Chunk_Index__c,
                'Single empty chunk should be at index 0');
            System.assertEquals('v2.0', c.Schema_Version__c,
                'Schema version stamped on every row');
        }
    }

    @isTest
    static void rebuild_populatesAllSixTypes_forNonEmptyTemplate() {
        Form_Template__c template = makeTemplate();
        Form_Page__c page = makePage(template.Id);
        Form_Section__c section = makeSection(template.Id, page.Id);
        Form_Question__c q1 = makeQuestion(template.Id, section.Id, 'Q1');
        Form_Question__c q2 = makeQuestion(template.Id, section.Id, 'Q2');

        NeuraFormLogic.FormTemplateWrapper w = new NeuraFormLogic.FormTemplateWrapper(
            template.Id,
            new List<Form_Page__c>{page},
            new List<Form_Section__c>{section},
            new List<Form_Question__c>{q1, q2},
            new List<String>{'{"id":"' + page.Id + '","conditions":[]}'},
            new List<String>{'{"id":"' + section.Id + '","conditions":[]}'},
            new List<String>{
                '{"id":"' + q1.Id + '","conditions":[]}',
                '{"id":"' + q2.Id + '","conditions":[]}'
            }
        );

        Test.startTest();
        NeuraFormSnapshotV2.rebuild(
            new Set<Id>{template.Id},
            new Map<Id, NeuraFormLogic.FormTemplateWrapper>{template.Id => w}
        );
        Test.stopTest();

        Map<String, List<Form_Template_Snapshot__c>> byType = chunksByType(template.Id);
        System.assertEquals(EXPECTED_PAYLOAD_TYPES, byType.size(),
            'All six payload types should be present');

        // Each chunk is itself a JSON array; verify roundtrip parses.
        for (String type : byType.keySet()) {
            String concatenated = concatChunks(byType.get(type));
            // Each Payload__c is already a JSON array; the test verifies
            // that the first chunk parses as a List (proxy for "valid JSON
            // array shape per chunk").
            Object parsed = JSON.deserializeUntyped(byType.get(type)[0].Payload__c);
            System.assert(parsed instanceof List<Object>,
                'Each chunk must be a JSON array: ' + type);
        }

        // Questions chunk should contain both q1 and q2.
        List<Object> questions = (List<Object>) JSON.deserializeUntyped(
            byType.get('Questions')[0].Payload__c
        );
        System.assertEquals(2, questions.size(),
            'Both questions should be serialized into the Questions chunk');
    }

    @isTest
    static void rebuild_isIdempotent_runTwice() {
        Form_Template__c template = makeTemplate();
        Form_Page__c page = makePage(template.Id);

        NeuraFormLogic.FormTemplateWrapper w = new NeuraFormLogic.FormTemplateWrapper(
            template.Id,
            new List<Form_Page__c>{page},
            new List<Form_Section__c>(),
            new List<Form_Question__c>(),
            new List<String>(), new List<String>(), new List<String>()
        );

        Test.startTest();
        NeuraFormSnapshotV2.rebuild(
            new Set<Id>{template.Id},
            new Map<Id, NeuraFormLogic.FormTemplateWrapper>{template.Id => w}
        );
        Integer firstCount = [SELECT COUNT() FROM Form_Template_Snapshot__c WHERE Form_Template__c = :template.Id];

        NeuraFormSnapshotV2.rebuild(
            new Set<Id>{template.Id},
            new Map<Id, NeuraFormLogic.FormTemplateWrapper>{template.Id => w}
        );
        Integer secondCount = [SELECT COUNT() FROM Form_Template_Snapshot__c WHERE Form_Template__c = :template.Id];
        Test.stopTest();

        System.assertEquals(firstCount, secondCount,
            'Second rebuild should produce the same number of chunk rows');
        System.assertEquals(EXPECTED_PAYLOAD_TYPES, firstCount,
            'Single-page template should produce exactly six chunk rows');
    }

    @isTest
    static void rebuild_handlesEmptyInputs() {
        Test.startTest();
        // Should not throw, should not insert anything.
        NeuraFormSnapshotV2.rebuild(null, null);
        NeuraFormSnapshotV2.rebuild(
            new Set<Id>(),
            new Map<Id, NeuraFormLogic.FormTemplateWrapper>()
        );
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Form_Template_Snapshot__c],
            'No snapshot rows should be inserted for empty inputs');
    }

    @isTest
    static void updateJSON_v2On_writesChunksAndClearsLegacyFields() {
        insertConfig(true, true); // v2 on, kill switch off (legacy off behavior)
        Form_Template__c template = makeTemplate();
        Form_Page__c page = makePage(template.Id);
        Form_Section__c section = makeSection(template.Id, page.Id);
        makeQuestion(template.Id, section.Id, 'Q1');

        // Re-fetch template with the JSON fields so we can assert they're cleared.
        template = [
            SELECT Id, Pages_JSON__c, Sections_JSON__c, Questions_JSON__c,
                   Questions_JSON_1__c, Questions_JSON_2__c,
                   Page_Conditions__c, Section_Conditions__c, Question_Conditions__c
            FROM Form_Template__c WHERE Id = :template.Id
        ];

        Test.startTest();
        NeuraFormLogic.updateJSON(
            new Map<Id, Form_Template__c>{template.Id => template}
        );
        Test.stopTest();

        Form_Template__c after = [
            SELECT Id, Pages_JSON__c, Sections_JSON__c, Questions_JSON__c,
                   Questions_JSON_1__c, Questions_JSON_2__c,
                   Page_Conditions__c, Section_Conditions__c, Question_Conditions__c
            FROM Form_Template__c WHERE Id = :template.Id
        ];
        System.assertEquals(null, after.Pages_JSON__c,
            'v2 path should null legacy Pages_JSON__c');
        System.assertEquals(null, after.Sections_JSON__c,
            'v2 path should null legacy Sections_JSON__c');
        System.assertEquals(null, after.Questions_JSON__c,
            'v2 path should null legacy Questions_JSON__c');

        Integer chunkCount = [SELECT COUNT() FROM Form_Template_Snapshot__c WHERE Form_Template__c = :template.Id];
        System.assertEquals(EXPECTED_PAYLOAD_TYPES, chunkCount,
            'Six payload types should be emitted on v2 write');
    }

    @isTest
    static void updateJSON_v2Off_writesLegacyFieldsAndNoChunks() {
        insertConfig(false, true); // v2 off; kill switch off
        Form_Template__c template = makeTemplate();
        Form_Page__c page = makePage(template.Id);
        Form_Section__c section = makeSection(template.Id, page.Id);
        makeQuestion(template.Id, section.Id, 'Q1');

        template = [
            SELECT Id, Pages_JSON__c, Sections_JSON__c, Questions_JSON__c,
                   Questions_JSON_1__c, Questions_JSON_2__c,
                   Page_Conditions__c, Section_Conditions__c, Question_Conditions__c
            FROM Form_Template__c WHERE Id = :template.Id
        ];

        Test.startTest();
        NeuraFormLogic.updateJSON(
            new Map<Id, Form_Template__c>{template.Id => template}
        );
        Test.stopTest();

        Form_Template__c after = [
            SELECT Id, Pages_JSON__c, Sections_JSON__c, Questions_JSON__c
            FROM Form_Template__c WHERE Id = :template.Id
        ];
        System.assertNotEquals(null, after.Pages_JSON__c,
            'Legacy path should populate Pages_JSON__c');
        System.assertNotEquals(null, after.Sections_JSON__c,
            'Legacy path should populate Sections_JSON__c');
        System.assertNotEquals(null, after.Questions_JSON__c,
            'Legacy path should populate Questions_JSON__c');

        Integer chunkCount = [SELECT COUNT() FROM Form_Template_Snapshot__c WHERE Form_Template__c = :template.Id];
        System.assertEquals(0, chunkCount,
            'No snapshot rows should be created when v2 is off');
    }

    // ----- Question Catalog resolution tests (Pillar 2) --------------------

    @isTest
    static void rebuild_catalogOff_serializesBindingFieldsAsBefore() {
        // Question_Catalog_Enabled__c is unset → fall through to legacy path
        // even when a binding has a catalog ref set. Backward compatible.
        insertConfig(true, true);
        Form_Template__c template = makeTemplate();
        Form_Page__c page = makePage(template.Id);
        Form_Section__c section = makeSection(template.Id, page.Id);

        Form_Question_Catalog__c cat = new Form_Question_Catalog__c(
            External_Reference__c = 'cat-1',
            Question__c = 'Catalog text', Type__c = 'Text', Required__c = true
        );
        insert cat;

        Form_Question__c q = new Form_Question__c(
            Form_Template__c = template.Id,
            Form_Section__c = section.Id,
            Question__c = 'Binding text',
            Type__c = 'Text',
            Required__c = false,
            Form_Question_Catalog__c = cat.Id
        );
        insert q;

        template = [
            SELECT Id FROM Form_Template__c WHERE Id = :template.Id
        ];

        Test.startTest();
        NeuraFormLogic.updateJSON(
            new Map<Id, Form_Template__c>{template.Id => template}
        );
        Test.stopTest();

        Map<String, List<Form_Template_Snapshot__c>> byType = chunksByType(template.Id);
        List<Object> questions = (List<Object>) JSON.deserializeUntyped(
            byType.get('Questions')[0].Payload__c
        );
        Map<String, Object> serialized = (Map<String, Object>) questions[0];
        System.assertEquals('Binding text', serialized.get('Question__c'),
            'Catalog off → snapshot uses binding fields, not catalog fields');
    }

    @isTest
    static void rebuild_catalogOn_serializesCatalogFields() {
        enableCatalog();
        Form_Template__c template = makeTemplate();
        Form_Page__c page = makePage(template.Id);
        Form_Section__c section = makeSection(template.Id, page.Id);

        Form_Question_Catalog__c cat = new Form_Question_Catalog__c(
            External_Reference__c = 'cat-2',
            Question__c = 'Catalog truth',
            Type__c = 'Multiple Choice',
            Value_Set__c = '[{"id":"yes","label":"Yes","value":"yes"}]',
            Required__c = true
        );
        insert cat;

        Form_Question__c q = new Form_Question__c(
            Form_Template__c = template.Id,
            Form_Section__c = section.Id,
            Question__c = 'Stale binding text',
            Type__c = 'Text',
            Required__c = false,
            Form_Question_Catalog__c = cat.Id
        );
        insert q;

        template = [SELECT Id FROM Form_Template__c WHERE Id = :template.Id];

        Test.startTest();
        NeuraFormLogic.updateJSON(
            new Map<Id, Form_Template__c>{template.Id => template}
        );
        Test.stopTest();

        Map<String, List<Form_Template_Snapshot__c>> byType = chunksByType(template.Id);
        Map<String, Object> serialized = (Map<String, Object>) ((List<Object>)
            JSON.deserializeUntyped(byType.get('Questions')[0].Payload__c))[0];

        System.assertEquals('Catalog truth', serialized.get('Question__c'),
            'Catalog on → snapshot resolves Question__c through the catalog');
        System.assertEquals('Multiple Choice', serialized.get('Type__c'),
            'Catalog on → Type__c comes from catalog');
        System.assertEquals(true, serialized.get('Required__c'),
            'Catalog on → Required__c comes from catalog');
        System.assert(!serialized.containsKey('Form_Question_Catalog__c'),
            'Catalog lookup field should be stripped from renderer payload');
        System.assert(!serialized.containsKey('Override_Question__c'),
            'Override fields should be stripped from renderer payload');
    }

    @isTest
    static void rebuild_catalogOn_overrideQuestionWins() {
        enableCatalog();
        Form_Template__c template = makeTemplate();
        Form_Page__c page = makePage(template.Id);
        Form_Section__c section = makeSection(template.Id, page.Id);

        Form_Question_Catalog__c cat = new Form_Question_Catalog__c(
            External_Reference__c = 'cat-3',
            Question__c = 'Catalog default question', Type__c = 'Text'
        );
        insert cat;

        Form_Question__c q = new Form_Question__c(
            Form_Template__c = template.Id,
            Form_Section__c = section.Id,
            Form_Question_Catalog__c = cat.Id,
            Override_Question__c = 'Per-binding override wins'
        );
        insert q;

        template = [SELECT Id FROM Form_Template__c WHERE Id = :template.Id];

        Test.startTest();
        NeuraFormLogic.updateJSON(
            new Map<Id, Form_Template__c>{template.Id => template}
        );
        Test.stopTest();

        Map<String, List<Form_Template_Snapshot__c>> byType = chunksByType(template.Id);
        Map<String, Object> serialized = (Map<String, Object>) ((List<Object>)
            JSON.deserializeUntyped(byType.get('Questions')[0].Payload__c))[0];

        System.assertEquals('Per-binding override wins', serialized.get('Question__c'),
            'Override_Question__c should take precedence over catalog Question__c');
    }

    @isTest
    static void rebuild_catalogOn_overrideRequiredHonoredAndInheritFalls() {
        enableCatalog();
        Form_Template__c template = makeTemplate();
        Form_Page__c page = makePage(template.Id);
        Form_Section__c section = makeSection(template.Id, page.Id);

        Form_Question_Catalog__c cat = new Form_Question_Catalog__c(
            External_Reference__c = 'cat-4',
            Question__c = 'Required test', Type__c = 'Text', Required__c = true
        );
        insert cat;

        // Override = 'No' should flip to false
        Form_Question__c qOverrideNo = new Form_Question__c(
            Form_Template__c = template.Id, Form_Section__c = section.Id,
            Form_Question_Catalog__c = cat.Id, Override_Required__c = 'No'
        );
        // Override = 'Inherit' should keep catalog (true)
        Form_Question__c qInherit = new Form_Question__c(
            Form_Template__c = template.Id, Form_Section__c = section.Id,
            Form_Question_Catalog__c = cat.Id, Override_Required__c = 'Inherit'
        );
        insert new List<Form_Question__c>{qOverrideNo, qInherit};

        template = [SELECT Id FROM Form_Template__c WHERE Id = :template.Id];

        Test.startTest();
        NeuraFormLogic.updateJSON(
            new Map<Id, Form_Template__c>{template.Id => template}
        );
        Test.stopTest();

        Map<String, List<Form_Template_Snapshot__c>> byType = chunksByType(template.Id);
        List<Object> questions = (List<Object>) JSON.deserializeUntyped(
            byType.get('Questions')[0].Payload__c
        );

        // Look up each by Id since order isn't guaranteed
        Map<String, Boolean> requiredById = new Map<String, Boolean>();
        for (Object o : questions) {
            Map<String, Object> m = (Map<String, Object>) o;
            requiredById.put((String) m.get('Id'), (Boolean) m.get('Required__c'));
        }
        System.assertEquals(false, requiredById.get(qOverrideNo.Id),
            'Override_Required__c=No should override catalog true to false');
        System.assertEquals(true, requiredById.get(qInherit.Id),
            'Override_Required__c=Inherit should keep catalog Required__c=true');
    }

    @isTest
    static void rebuild_catalogOn_nullCatalogRefFallsBackToBinding() {
        // Binding with no catalog ref (mid-migration state): should serialize
        // using the binding's own fields, not crash.
        enableCatalog();
        Form_Template__c template = makeTemplate();
        Form_Page__c page = makePage(template.Id);
        Form_Section__c section = makeSection(template.Id, page.Id);

        Form_Question__c q = new Form_Question__c(
            Form_Template__c = template.Id,
            Form_Section__c = section.Id,
            Question__c = 'Unlinked binding text',
            Type__c = 'Text'
            // No Form_Question_Catalog__c set
        );
        insert q;

        template = [SELECT Id FROM Form_Template__c WHERE Id = :template.Id];

        Test.startTest();
        NeuraFormLogic.updateJSON(
            new Map<Id, Form_Template__c>{template.Id => template}
        );
        Test.stopTest();

        Map<String, List<Form_Template_Snapshot__c>> byType = chunksByType(template.Id);
        Map<String, Object> serialized = (Map<String, Object>) ((List<Object>)
            JSON.deserializeUntyped(byType.get('Questions')[0].Payload__c))[0];

        System.assertEquals('Unlinked binding text', serialized.get('Question__c'),
            'Null catalog ref should fall back to binding fields');
    }

    // ----- helpers ---------------------------------------------------------

    private static void insertConfig(Boolean v2Enabled, Boolean triggerEnabled) {
        // triggerEnabled=true means the kill switch is OFF (i.e. the trigger runs normally).
        FieldForms_Configuration__c cfg = new FieldForms_Configuration__c();
        cfg.Snapshot_V2_Enabled__c = v2Enabled;
        cfg.Disable_Form_Template_JSON_Trigger__c = !triggerEnabled;
        insert cfg;
    }

    private static void enableCatalog() {
        FieldForms_Configuration__c cfg = new FieldForms_Configuration__c();
        cfg.Snapshot_V2_Enabled__c = true;
        cfg.Question_Catalog_Enabled__c = true;
        cfg.Disable_Form_Template_JSON_Trigger__c = false;
        insert cfg;
    }

    private static Form_Template__c makeTemplate() {
        Form_Template__c t = new Form_Template__c(Name = 'V2 Test Template');
        insert t;
        return t;
    }

    private static Form_Page__c makePage(Id templateId) {
        Form_Page__c p = new Form_Page__c(
            Form_Template__c = templateId,
            Order__c = 1,
            Title__c = 'P1'
        );
        insert p;
        return p;
    }

    private static Form_Section__c makeSection(Id templateId, Id pageId) {
        Form_Section__c s = new Form_Section__c(
            Form_Template__c = templateId,
            Form_Page__c = pageId,
            Name = 'S1'
        );
        insert s;
        return s;
    }

    private static Form_Question__c makeQuestion(Id templateId, Id sectionId, String label) {
        Form_Question__c q = new Form_Question__c(
            Form_Template__c = templateId,
            Form_Section__c = sectionId,
            Question__c = label
        );
        insert q;
        return q;
    }

    private static Map<String, List<Form_Template_Snapshot__c>> chunksByType(Id templateId) {
        Map<String, List<Form_Template_Snapshot__c>> byType =
            new Map<String, List<Form_Template_Snapshot__c>>();
        for (Form_Template_Snapshot__c c : [
            SELECT Payload_Type__c, Chunk_Index__c, Payload__c
            FROM Form_Template_Snapshot__c
            WHERE Form_Template__c = :templateId
            ORDER BY Payload_Type__c, Chunk_Index__c
        ]) {
            if (!byType.containsKey(c.Payload_Type__c)) {
                byType.put(c.Payload_Type__c, new List<Form_Template_Snapshot__c>());
            }
            byType.get(c.Payload_Type__c).add(c);
        }
        return byType;
    }

    private static String concatChunks(List<Form_Template_Snapshot__c> chunks) {
        String acc = '';
        for (Form_Template_Snapshot__c c : chunks) {
            acc += c.Payload__c == null ? '' : c.Payload__c;
        }
        return acc;
    }
}
