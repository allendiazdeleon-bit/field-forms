@isTest
private class NeuraFormBrandControllerTest {

    private static final String BRAND_SCOPE = 'BURGER_KING';

    @testSetup
    static void setup() {
        // A template already in the brand's scope, with a small page/section/
        // question graph so clone has something real to deep-copy.
        Form_Template__c scoped = new Form_Template__c(
            Name = 'BK Opening Checklist',
            Scope__c = BRAND_SCOPE,
            Status__c = 'Active'
        );
        insert scoped;

        Form_Page__c page = new Form_Page__c(
            Name = 'Page 1', Order__c = 1, Title__c = 'Page 1',
            Form_Template__c = scoped.Id
        );
        insert page;

        Form_Section__c section = new Form_Section__c(
            Name = 'Section 1', Order__c = 1, Title__c = 'Section 1',
            Form_Template__c = scoped.Id, Form_Page__c = page.Id
        );
        insert section;

        insert new Form_Question__c(
            Order__c = 1, Question__c = 'Is the lobby clean?',
            Form_Template__c = scoped.Id, Form_Section__c = section.Id, Form_Page__c = page.Id
        );

        // A global (null scope) template that any brand can clone from.
        insert new Form_Template__c(Name = 'Global Safety Form', Status__c = 'Active');

        // A retired template that must NOT appear in clone candidates.
        insert new Form_Template__c(
            Name = 'Old BK Form', Scope__c = BRAND_SCOPE, Status__c = 'Retired'
        );

        insert new Account(Name = 'Burger King');
    }

    @isTest
    static void getBrandContextReturnsScope() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Burger King' LIMIT 1];

        Test.startTest();
        Account ctx = NeuraFormBrandController.getBrandContext(acct.Id);
        Test.stopTest();

        System.assertNotEquals(null, ctx, 'Expected the account back');
        System.assertEquals('Burger King', ctx.Name);
    }

    @isTest
    static void setAccountScopeStampsBrandKey() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Burger King' LIMIT 1];

        Test.startTest();
        NeuraFormBrandController.setAccountScope(acct.Id, BRAND_SCOPE);
        Test.stopTest();

        System.assertEquals(BRAND_SCOPE,
            [SELECT Form_Scope__c FROM Account WHERE Id = :acct.Id].Form_Scope__c);
    }

    @isTest
    static void setAccountScopeRejectsBlank() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Burger King' LIMIT 1];
        Boolean threw = false;
        try {
            NeuraFormBrandController.setAccountScope(acct.Id, '  ');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Blank scope should be rejected');
    }

    @isTest
    static void listTemplatesForScopeReturnsOnlyBrand() {
        Test.startTest();
        List<Form_Template__c> rows = NeuraFormBrandController.listTemplatesForScope(BRAND_SCOPE);
        Test.stopTest();

        System.assertEquals(2, rows.size(), 'Both BK-scoped templates (active + retired) expected');
        for (Form_Template__c t : rows) {
            System.assertEquals(BRAND_SCOPE, t.Scope__c, 'Only brand-scoped rows expected');
        }
    }

    @isTest
    static void listTemplatesForScopeBlankReturnsEmpty() {
        System.assertEquals(0, NeuraFormBrandController.listTemplatesForScope(null).size(),
            'Blank scope must not leak templates');
        System.assertEquals(0, NeuraFormBrandController.listTemplatesForScope('').size(),
            'Blank scope must not leak templates');
    }

    @isTest
    static void listClonableExcludesRetiredIncludesGlobal() {
        Test.startTest();
        List<Form_Template__c> rows = NeuraFormBrandController.listClonableTemplates(BRAND_SCOPE);
        Test.stopTest();

        Set<String> names = new Set<String>();
        for (Form_Template__c t : rows) names.add(t.Name);
        System.assert(names.contains('BK Opening Checklist'), 'In-scope active template expected');
        System.assert(names.contains('Global Safety Form'), 'Global template expected');
        System.assert(!names.contains('Old BK Form'), 'Retired template must be excluded');
    }

    @isTest
    static void createBlankStampsScopeAndDraft() {
        Test.startTest();
        Form_Template__c created = NeuraFormBrandController.createBlankTemplate('New BK Form', BRAND_SCOPE);
        Test.stopTest();

        Form_Template__c reloaded = [
            SELECT Name, Scope__c, Status__c FROM Form_Template__c WHERE Id = :created.Id
        ];
        System.assertEquals('New BK Form', reloaded.Name);
        System.assertEquals(BRAND_SCOPE, reloaded.Scope__c);
        System.assertEquals('Draft', reloaded.Status__c, 'New forms start as Draft');
    }

    @isTest
    static void createBlankRequiresName() {
        Boolean threw = false;
        try {
            NeuraFormBrandController.createBlankTemplate('  ', BRAND_SCOPE);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Blank name should be rejected');
    }

    @isTest
    static void cloneDeepCopiesIntoBrandScopeAsDraft() {
        Form_Template__c source = [
            SELECT Id FROM Form_Template__c WHERE Name = 'BK Opening Checklist' LIMIT 1
        ];

        Test.startTest();
        Form_Template__c copy = NeuraFormBrandController.cloneTemplate(
            source.Id, 'BK Opening Checklist v2', BRAND_SCOPE
        );
        Test.stopTest();

        System.assertNotEquals(source.Id, copy.Id, 'Clone must be a new record');
        Form_Template__c reloaded = [
            SELECT Name, Scope__c, Status__c FROM Form_Template__c WHERE Id = :copy.Id
        ];
        System.assertEquals('BK Opening Checklist v2', reloaded.Name);
        System.assertEquals(BRAND_SCOPE, reloaded.Scope__c);
        System.assertEquals('Draft', reloaded.Status__c, 'Clones start as Draft');

        Integer copiedQuestions = [
            SELECT COUNT() FROM Form_Question__c WHERE Form_Template__c = :copy.Id
        ];
        System.assert(copiedQuestions > 0, 'Clone should bring over the question graph');
    }

    @isTest
    static void cloneWorksWhenExternalRefsAreNotRecordIds() {
        // AI doc-imports stamp AIGEN_ External_Reference__c values (and
        // cross-org imports keep origin refs). The export's child FK fields
        // hold source IDs while import resolution maps are keyed by extref —
        // without the refAliases bridge, pages imported with a null
        // Form_Template__c and the whole clone rolled back
        // (REQUIRED_FIELD_MISSING).
        Form_Template__c source = [
            SELECT Id FROM Form_Template__c WHERE Name = 'BK Opening Checklist' LIMIT 1
        ];
        source.External_Reference__c = 'AIGEN_tpl_123';
        update source;
        List<Form_Page__c> srcPages = [
            SELECT Id FROM Form_Page__c WHERE Form_Template__c = :source.Id
        ];
        for (Integer i = 0; i < srcPages.size(); i++) {
            srcPages[i].External_Reference__c = 'AIGEN_p_' + i;
        }
        update srcPages;

        Test.startTest();
        Form_Template__c copy = NeuraFormBrandController.cloneTemplate(
            source.Id, 'AIGEN Clone', BRAND_SCOPE
        );
        Test.stopTest();

        System.assertNotEquals(source.Id, copy.Id);
        System.assertEquals(srcPages.size(), [
            SELECT COUNT() FROM Form_Page__c WHERE Form_Template__c = :copy.Id
        ], 'Every page must come across linked to the clone.');
        System.assert([
            SELECT COUNT() FROM Form_Question__c WHERE Form_Template__c = :copy.Id
        ] > 0, 'Question graph must come across.');
    }

    @isTest
    static void clonePreservesRebuiltSnapshotFragments() {
        Form_Template__c source = [
            SELECT Id FROM Form_Template__c WHERE Name = 'BK Opening Checklist' LIMIT 1
        ];

        Test.startTest();
        Form_Template__c copy = NeuraFormBrandController.cloneTemplate(
            source.Id, 'Snapshot Check', BRAND_SCOPE
        );
        Test.stopTest();

        // The post-import stamp must be SPARSE: a full-record update would
        // rewrite the Questions_JSON_*__c snapshot importTemplatesAsNew just
        // rebuilt, re-pointing it at source-org question Ids. The rebuilt
        // snapshot references the CLONE's questions, so spot-check that any
        // question Id appearing in it belongs to the copy, not the source.
        Form_Template__c reloaded = [
            SELECT Questions_JSON__c, Questions_JSON_1__c, Questions_JSON_2__c
            FROM Form_Template__c WHERE Id = :copy.Id
        ];
        String snapshot = (reloaded.Questions_JSON__c == null ? '' : reloaded.Questions_JSON__c)
            + (reloaded.Questions_JSON_1__c == null ? '' : reloaded.Questions_JSON_1__c)
            + (reloaded.Questions_JSON_2__c == null ? '' : reloaded.Questions_JSON_2__c);
        for (Form_Question__c srcQ : [
            SELECT Id FROM Form_Question__c WHERE Form_Template__c = :source.Id
        ]) {
            System.assert(!snapshot.contains(String.valueOf(srcQ.Id)),
                'Clone snapshot must not reference source-org question Ids.');
        }
    }

    @isTest
    static void assignScopeStampsImportedTemplates() {
        Form_Template__c imported = new Form_Template__c(Name = 'Imported Form');
        insert imported; // null scope, null status (as a fresh import would be)

        Test.startTest();
        NeuraFormBrandController.assignScope(new List<Id>{ imported.Id }, BRAND_SCOPE);
        Test.stopTest();

        Form_Template__c reloaded = [
            SELECT Scope__c, Status__c FROM Form_Template__c WHERE Id = :imported.Id
        ];
        System.assertEquals(BRAND_SCOPE, reloaded.Scope__c);
        System.assertEquals('Draft', reloaded.Status__c, 'Imported forms default to Draft');
    }

    @isTest
    static void setStatusFlipsAndValidates() {
        Form_Template__c draft = NeuraFormBrandController.createBlankTemplate('Flip Me', BRAND_SCOPE);

        Test.startTest();
        NeuraFormBrandController.setTemplateStatus(draft.Id, 'Active');
        Boolean threw = false;
        try {
            NeuraFormBrandController.setTemplateStatus(draft.Id, 'Bogus');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Unknown status must be rejected');
        System.assertEquals('Active',
            [SELECT Status__c FROM Form_Template__c WHERE Id = :draft.Id].Status__c);
    }
}
