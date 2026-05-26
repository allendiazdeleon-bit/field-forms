/**
 * Coverage for NeuraFormCatalogBackfillBatch. Verifies:
 *   - happy path creates one catalog entry per binding
 *   - content fields are copied verbatim from binding to catalog
 *   - idempotency: re-running skips already-linked bindings
 *   - templateIdScope honors the constructor filter
 *   - empty org runs cleanly with no errors
 *
 * All tests run with Disable_Form_Template_JSON_Trigger__c = true so
 * we don't trip the snapshot queueable during DML setup.
 */
@isTest
private class NeuraFormCatalogBackfillBatchTest {

    @isTest
    static void backfill_createsCatalogForBindingsWithoutOne() {
        suppressSnapshotTrigger();
        Form_Template__c t = makeTemplate('T1');
        Form_Question__c q = makeQuestion(t.Id, 'Test question?', 'Text');

        System.assertEquals(0, [SELECT COUNT() FROM Form_Question_Catalog__c]);

        Test.startTest();
        Database.executeBatch(new NeuraFormCatalogBackfillBatch(), 200);
        Test.stopTest();

        // One catalog entry created
        List<Form_Question_Catalog__c> catalogs = [
            SELECT Id, External_Reference__c, Question__c, Type__c
            FROM Form_Question_Catalog__c
        ];
        System.assertEquals(1, catalogs.size(),
            'Backfill should create one catalog entry for the binding');
        System.assertEquals('Test question?', catalogs[0].Question__c);
        System.assertEquals('Text', catalogs[0].Type__c);
        System.assertEquals('cat_' + q.Id, catalogs[0].External_Reference__c,
            'External_Reference__c should be derived from the binding Id');

        // Binding now points at the catalog entry
        Form_Question__c boundQ = [
            SELECT Form_Question_Catalog__c FROM Form_Question__c WHERE Id = :q.Id
        ];
        System.assertEquals(catalogs[0].Id, boundQ.Form_Question_Catalog__c,
            'Binding should be linked to its newly-created catalog entry');
    }

    @isTest
    static void backfill_copiesAllContentFields() {
        suppressSnapshotTrigger();
        Form_Template__c t = makeTemplate('T2');
        // A "rich" question with most of the content fields populated.
        Form_Question__c q = new Form_Question__c(
            Form_Template__c = t.Id,
            Question__c = 'Rich question with all fields',
            Type__c = 'Multiple Choice',
            Value_Set__c = '[{"id":"opt1","label":"Opt 1","value":"v1"}]',
            Required__c = true,
            Include_Comment__c = true,
            Include_Photo__c = true,
            Display_Rich_Text__c = '<p>Display rich text content</p>',
            Label_Visible__c = false,
            Text_Alignment__c = 'left',
            Font_Color__c = '#000000',
            Font_Size__c = '14',
            Length__c = 255,
            Decimal_Places__c = 2,
            Min__c = 0,
            Max__c = 100,
            Slider_Size__c = 'medium',
            Slider_Step__c = 1,
            Active_Message__c = 'Active message',
            Inactive_Message__c = 'Inactive message',
            Default_Value_Source__c = 'WorkOrder.Subject',
            Default_Value_Static__c = 'default value',
            Calculation_Formula__c = 'a + b',
            Calculation_Result_Format__c = 'Decimal',
            Date_Time_Save_Format__c = 'YYYY-MM-DD',
            Lookup_Child_Object__c = 'Account',
            Lookup_Display_Field__c = 'Name',
            Lookup_Related_List__c = 'Contacts',
            Layout_Item__c = true
        );
        insert q;

        Test.startTest();
        Database.executeBatch(new NeuraFormCatalogBackfillBatch(), 200);
        Test.stopTest();

        Form_Question_Catalog__c cat = [
            SELECT Id, Question__c, Type__c, Value_Set__c, Required__c,
                   Include_Comment__c, Include_Photo__c, Display_Rich_Text__c,
                   Label_Visible__c, Text_Alignment__c, Font_Color__c, Font_Size__c,
                   Length__c, Decimal_Places__c, Min__c, Max__c,
                   Slider_Size__c, Slider_Step__c,
                   Active_Message__c, Inactive_Message__c,
                   Default_Value_Source__c, Default_Value_Static__c,
                   Calculation_Formula__c, Calculation_Result_Format__c,
                   Date_Time_Save_Format__c,
                   Lookup_Child_Object__c, Lookup_Display_Field__c, Lookup_Related_List__c,
                   Layout_Item__c
            FROM Form_Question_Catalog__c LIMIT 1
        ];

        // Spot-check that every field made it across.
        System.assertEquals(q.Question__c, cat.Question__c);
        System.assertEquals(q.Type__c, cat.Type__c);
        System.assertEquals(q.Value_Set__c, cat.Value_Set__c);
        System.assertEquals(q.Required__c, cat.Required__c);
        System.assertEquals(q.Include_Comment__c, cat.Include_Comment__c);
        System.assertEquals(q.Include_Photo__c, cat.Include_Photo__c);
        System.assertEquals(q.Display_Rich_Text__c, cat.Display_Rich_Text__c);
        System.assertEquals(q.Label_Visible__c, cat.Label_Visible__c);
        System.assertEquals(q.Text_Alignment__c, cat.Text_Alignment__c);
        System.assertEquals(q.Font_Color__c, cat.Font_Color__c);
        System.assertEquals(q.Font_Size__c, cat.Font_Size__c);
        System.assertEquals(q.Length__c, cat.Length__c);
        System.assertEquals(q.Decimal_Places__c, cat.Decimal_Places__c);
        System.assertEquals(q.Min__c, cat.Min__c);
        System.assertEquals(q.Max__c, cat.Max__c);
        System.assertEquals(q.Slider_Size__c, cat.Slider_Size__c);
        System.assertEquals(q.Slider_Step__c, cat.Slider_Step__c);
        System.assertEquals(q.Active_Message__c, cat.Active_Message__c);
        System.assertEquals(q.Inactive_Message__c, cat.Inactive_Message__c);
        System.assertEquals(q.Default_Value_Source__c, cat.Default_Value_Source__c);
        System.assertEquals(q.Default_Value_Static__c, cat.Default_Value_Static__c);
        System.assertEquals(q.Calculation_Formula__c, cat.Calculation_Formula__c);
        System.assertEquals(q.Calculation_Result_Format__c, cat.Calculation_Result_Format__c);
        System.assertEquals(q.Date_Time_Save_Format__c, cat.Date_Time_Save_Format__c);
        System.assertEquals(q.Lookup_Child_Object__c, cat.Lookup_Child_Object__c);
        System.assertEquals(q.Lookup_Display_Field__c, cat.Lookup_Display_Field__c);
        System.assertEquals(q.Lookup_Related_List__c, cat.Lookup_Related_List__c);
        System.assertEquals(q.Layout_Item__c, cat.Layout_Item__c);
    }

    @isTest
    static void backfill_isIdempotent_skipsAlreadyLinkedBindings() {
        // Idempotency depends on the start() WHERE clause filtering out
        // bindings whose Form_Question_Catalog__c is already set. Test the
        // invariant directly: pre-populate a catalog and link a binding to
        // it, then run the batch and assert no new catalog rows appear.
        // Running the batch twice in one test method doesn't work — both
        // executeBatch calls see the same pre-batch state inside
        // Test.startTest/stopTest and collide on External_Reference__c
        // uniqueness.
        suppressSnapshotTrigger();
        Form_Template__c t = makeTemplate('T3');
        Form_Question__c q1 = makeQuestion(t.Id, 'Q1', 'Text');
        Form_Question__c q2 = makeQuestion(t.Id, 'Q2', 'Text');

        // Pretend a prior backfill already ran for both bindings.
        Form_Question_Catalog__c c1 = new Form_Question_Catalog__c(
            External_Reference__c = 'prior_q1', Question__c = 'Q1', Type__c = 'Text'
        );
        Form_Question_Catalog__c c2 = new Form_Question_Catalog__c(
            External_Reference__c = 'prior_q2', Question__c = 'Q2', Type__c = 'Text'
        );
        insert new List<Form_Question_Catalog__c>{c1, c2};

        q1.Form_Question_Catalog__c = c1.Id;
        q2.Form_Question_Catalog__c = c2.Id;
        update new List<Form_Question__c>{q1, q2};

        Test.startTest();
        Database.executeBatch(new NeuraFormCatalogBackfillBatch(), 200);
        Test.stopTest();

        Integer catalogCount = [SELECT COUNT() FROM Form_Question_Catalog__c];
        System.assertEquals(2, catalogCount,
            'Backfill should skip bindings that already have a catalog reference');
    }

    @isTest
    static void backfill_respectsTemplateIdScope() {
        suppressSnapshotTrigger();
        Form_Template__c t1 = makeTemplate('Scope T1');
        Form_Template__c t2 = makeTemplate('Scope T2');
        Form_Question__c q1 = makeQuestion(t1.Id, 'Q1', 'Text');
        Form_Question__c q2 = makeQuestion(t2.Id, 'Q2', 'Text');

        Test.startTest();
        Database.executeBatch(
            new NeuraFormCatalogBackfillBatch(new Set<Id>{t1.Id}),
            200
        );
        Test.stopTest();

        Form_Question__c q1After = [
            SELECT Form_Question_Catalog__c FROM Form_Question__c WHERE Id = :q1.Id
        ];
        Form_Question__c q2After = [
            SELECT Form_Question_Catalog__c FROM Form_Question__c WHERE Id = :q2.Id
        ];
        System.assertNotEquals(null, q1After.Form_Question_Catalog__c,
            'Scoped template binding should be linked');
        System.assertEquals(null, q2After.Form_Question_Catalog__c,
            'Out-of-scope template binding should remain unlinked');
    }

    @isTest
    static void backfill_emptyOrg_runsCleanly() {
        suppressSnapshotTrigger();

        Test.startTest();
        Database.executeBatch(new NeuraFormCatalogBackfillBatch(), 200);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Form_Question_Catalog__c],
            'Empty org should produce no catalog entries');
    }

    // ----- helpers ---------------------------------------------------------

    private static void suppressSnapshotTrigger() {
        FieldForms_Configuration__c cfg = new FieldForms_Configuration__c();
        cfg.Disable_Form_Template_JSON_Trigger__c = true;
        insert cfg;
    }

    private static Form_Template__c makeTemplate(String name) {
        Form_Template__c t = new Form_Template__c(Name = name);
        insert t;
        return t;
    }

    private static Form_Question__c makeQuestion(Id templateId, String text, String type) {
        Form_Page__c p = new Form_Page__c(
            Form_Template__c = templateId, Order__c = 1, Title__c = 'P'
        );
        insert p;
        Form_Section__c s = new Form_Section__c(
            Form_Template__c = templateId, Form_Page__c = p.Id, Name = 'S'
        );
        insert s;
        Form_Question__c q = new Form_Question__c(
            Form_Template__c = templateId,
            Form_Section__c = s.Id,
            Question__c = text,
            Type__c = type
        );
        insert q;
        return q;
    }
}
