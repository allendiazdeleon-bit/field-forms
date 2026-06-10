/**
 * Tests for NeuraFormBrandThemeController resolution precedence:
 * form-level > brand-level > global > stock fallback.
 */
@isTest
private class NeuraFormBrandThemeControllerTest {

    private static Form_Template__c tpl(String scope) {
        Form_Template__c t = new Form_Template__c(Name = 'Theme Test', Scope__c = scope);
        insert t;
        return t;
    }

    @isTest
    static void fallsBackToStockWhenNoThemes() {
        Form_Template__c t = tpl('ACME');
        Test.startTest();
        NeuraFormBrandThemeController.Theme theme =
            NeuraFormBrandThemeController.getThemeForTemplate(t.Id);
        Test.stopTest();
        System.assertEquals('default', theme.source);
        System.assertEquals('#0070d2', theme.primaryColor);
    }

    @isTest
    static void brandLevelWinsOverGlobal() {
        Form_Template__c t = tpl('ACME');
        insert new Brand_Theme__c(Primary_Color__c = '#000000'); // global
        insert new Brand_Theme__c(Scope__c = 'ACME', Primary_Color__c = '#E4002B'); // brand
        Test.startTest();
        NeuraFormBrandThemeController.Theme theme =
            NeuraFormBrandThemeController.getThemeForTemplate(t.Id);
        Test.stopTest();
        System.assertEquals('brand', theme.source);
        System.assertEquals('#E4002B', theme.primaryColor);
    }

    @isTest
    static void formLevelWinsOverBrand() {
        Form_Template__c t = tpl('ACME');
        insert new Brand_Theme__c(Scope__c = 'ACME', Primary_Color__c = '#E4002B'); // brand
        insert new Brand_Theme__c(Form_Template__c = t.Id, Primary_Color__c = '#6CA43A'); // form
        Test.startTest();
        NeuraFormBrandThemeController.Theme theme =
            NeuraFormBrandThemeController.getThemeForTemplate(t.Id);
        Test.stopTest();
        System.assertEquals('form', theme.source);
        System.assertEquals('#6CA43A', theme.primaryColor);
    }

    @isTest
    static void invalidColorsFallBackToStock() {
        Form_Template__c t = tpl('ACME');
        // A non-hex "color" can smuggle CSS into the PDF's <style> block —
        // toTheme must reject it and keep the stock palette. (The field is
        // Text(9), which caps the payload size but not its shape.)
        insert new Brand_Theme__c(
            Scope__c = 'ACME',
            Primary_Color__c = '#000;}x{',
            Secondary_Color__c = 'red'
        );
        NeuraFormBrandThemeController.Theme theme =
            NeuraFormBrandThemeController.getThemeForTemplate(t.Id);
        System.assertEquals(NeuraFormBrandThemeController.DEFAULT_PRIMARY, theme.primaryColor);
        System.assertEquals(NeuraFormBrandThemeController.DEFAULT_SECONDARY, theme.secondaryColor);
    }

    @isTest
    static void rejectsNonWebLogoUrls() {
        Form_Template__c t = tpl('ACME');
        insert new Brand_Theme__c(
            Scope__c = 'ACME', Primary_Color__c = '#E4002B',
            Logo_URL__c = 'javascript:alert(1)'
        );
        NeuraFormBrandThemeController.Theme theme =
            NeuraFormBrandThemeController.getThemeForTemplate(t.Id);
        System.assertEquals(null, theme.logoUrl, 'Only http(s)/relative logo URLs pass.');
    }

    @isTest
    static void secondActiveThemeAtSameTierIsBlocked() {
        // BrandThemeTrigger stops the ambiguity at save time; resolve()'s
        // newest-wins ordering remains as defense for pre-trigger data.
        tpl('ACME');
        insert new Brand_Theme__c(Scope__c = 'ACME', Primary_Color__c = '#111111');

        Database.SaveResult sr = Database.insert(
            new Brand_Theme__c(Scope__c = 'ACME', Primary_Color__c = '#222222'), false
        );
        System.assertEquals(false, sr.isSuccess(),
            'Two active themes for one scope make rendered branding ambiguous.');
        System.assert(sr.getErrors()[0].getMessage().contains('active theme already exists'),
            sr.getErrors()[0].getMessage());
    }

    @isTest
    static void activeThemesAtDifferentTiersCoexist() {
        Form_Template__c t = tpl('ACME');
        insert new Brand_Theme__c(Primary_Color__c = '#000000'); // global
        insert new Brand_Theme__c(Scope__c = 'ACME', Primary_Color__c = '#111111'); // brand
        insert new Brand_Theme__c(Form_Template__c = t.Id, Primary_Color__c = '#222222'); // form
        System.assertEquals(3, [SELECT COUNT() FROM Brand_Theme__c WHERE Active__c = true],
            'Global, brand, and form tiers are distinct levels — all may be active.');
    }

    @isTest
    static void resolvesForLinkedFormViaAccountScope() {
        Form_Template__c t = tpl('ACME');
        Account a = new Account(Name = 'Acme Store', Form_Scope__c = 'ACME');
        insert a;
        insert new Brand_Theme__c(Scope__c = 'ACME', Primary_Color__c = '#E4002B', Header_Text__c = 'Acme Inspection');
        Linked_Form__c lf = new Linked_Form__c(Form_Template__c = t.Id, Account__c = a.Id, Status__c = 'Completed');
        insert lf;
        Test.startTest();
        NeuraFormBrandThemeController.Theme theme =
            NeuraFormBrandThemeController.getThemeForLinkedForm(lf.Id);
        Test.stopTest();
        System.assertEquals('brand', theme.source);
        System.assertEquals('#E4002B', theme.primaryColor);
        System.assertEquals('Acme Inspection', theme.headerText);
    }
}
