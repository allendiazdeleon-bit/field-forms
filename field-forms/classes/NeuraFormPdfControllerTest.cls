/**
 * Tests for NeuraFormPdfController — the token merge (incl. the user-typed
 * token injection case), the template sanitizer, render-safe defaults on the
 * bad-id path, severity ordering, and idempotent PDF generation.
 */
@isTest
private class NeuraFormPdfControllerTest {

    private static NeuraFormPdfController.ReportData sampleData() {
        NeuraFormPdfController.ReportData rd = new NeuraFormPdfController.ReportData();
        rd.linkedFormName = 'LF-0001';
        rd.status = 'Completed';
        rd.brandHeaderText = 'Acme Compliance Report';
        rd.brandLogoUrl = 'https://example.com/logo.png';

        NeuraFormPdfController.QuestionRow row = new NeuraFormPdfController.QuestionRow();
        row.label = 'Freezer condition';
        row.value = 'Condensation present';
        NeuraFormPdfController.QuestionRow sneaky = new NeuraFormPdfController.QuestionRow();
        sneaky.label = 'Notes';
        sneaky.value = 'See {{answer:Freezer condition}} earlier';

        NeuraFormPdfController.SectionGroup sg = new NeuraFormPdfController.SectionGroup();
        sg.title = 'Cold storage';
        sg.rows = new List<NeuraFormPdfController.QuestionRow>{ row, sneaky };
        NeuraFormPdfController.PageGroup pg = new NeuraFormPdfController.PageGroup();
        pg.title = 'Page 1';
        pg.sections = new List<NeuraFormPdfController.SectionGroup>{ sg };
        rd.pages.add(pg);
        return rd;
    }

    @isTest
    static void mergesScalarAndAnswerTokens() {
        NeuraFormPdfController.ReportData rd = sampleData();
        String merged = NeuraFormPdfController.mergeOutputTemplate(
            '<div><h1>{{brand.headerText}}</h1>{{report.formName}}' +
            '<p>{{answer:Freezer condition}}</p>{{unknown.token}}</div>', rd
        );
        System.assert(merged.contains('Acme Compliance Report'));
        System.assert(merged.contains('LF-0001'));
        System.assert(merged.contains('Condensation present'));
        System.assert(merged.contains('{{unknown.token}}'),
            'Unknown tokens pass through literally so typos are visible in review.');
    }

    @isTest
    static void userTypedTokensAreNotReSubstituted() {
        NeuraFormPdfController.ReportData rd = sampleData();
        String merged = NeuraFormPdfController.mergeOutputTemplate(
            '<div>{{answer:Notes}}</div>', rd
        );
        // The Notes answer contains "{{answer:Freezer condition}}" — a single
        // merge pass must emit it as literal text, not the other answer.
        System.assert(merged.contains('{{answer:Freezer condition}}'),
            'A token typed inside an answer must surface as literal text: ' + merged);
        System.assertEquals(1, merged.countMatches('{{answer:Freezer condition}}'));
        System.assert(!merged.contains('Condensation present'),
            'The injected token must not pull in the other answer.');
    }

    @isTest
    static void escapesLogoUrlInImgAttribute() {
        NeuraFormPdfController.ReportData rd = sampleData();
        rd.brandLogoUrl = 'https://example.com/x.png" onerror="alert(1)';
        String merged = NeuraFormPdfController.mergeOutputTemplate('<div>{{brand.logo}}</div>', rd);
        System.assert(!merged.contains('.png" onerror'),
            'A quote in the logo URL must not break out of the src attribute: ' + merged);
        System.assert(merged.contains('&quot;'));
    }

    @isTest
    static void sanitizerStripsActiveContent() {
        String dirty = '<div onclick="steal()">ok<script>alert(1)</script>' +
            '<iframe src="https://evil"></iframe>' +
            '<a href="javascript:bad()">x</a><style>.findings{display:none}</style></div>';
        String clean = NeuraFormPdfController.sanitizeTemplateHtml(dirty);
        System.assert(!clean.containsIgnoreCase('<script'), clean);
        System.assert(!clean.containsIgnoreCase('<iframe'), clean);
        System.assert(!clean.containsIgnoreCase('onclick'), clean);
        System.assert(!clean.containsIgnoreCase('javascript:'), clean);
        System.assert(!clean.containsIgnoreCase('<style'), clean);
        System.assert(clean.contains('ok'), 'Inert content survives: ' + clean);
    }

    @isTest
    static void badIdYieldsRenderSafeData() {
        Form_Template__c tpl = new Form_Template__c(Name = 'T');
        insert tpl;
        Linked_Form__c lf = new Linked_Form__c(Form_Template__c = tpl.Id, Status__c = 'Completed');
        insert lf;
        delete lf; // a stale/deleted id is the realistic bad input

        NeuraFormPdfController.ReportData rd = NeuraFormPdfController.loadReportData(lf.Id);
        System.assertNotEquals(null, rd.findings, 'Collections must never be null for VF.');
        System.assertNotEquals(null, rd.pages);
        System.assertEquals(false, rd.hasSignature);
        System.assertEquals(false, rd.hasRenderedHtml);
        System.assertEquals(NeuraFormBrandThemeController.DEFAULT_PRIMARY, rd.brandPrimaryColor,
            'A null color would render "border: 3px solid ;" in the page styles.');
    }

    @isTest
    static void findingsRankBySeverityNotAlphabetically() {
        Form_Template__c tpl = new Form_Template__c(Name = 'T');
        insert tpl;
        Linked_Form__c lf = new Linked_Form__c(Form_Template__c = tpl.Id, Status__c = 'Completed');
        insert lf;
        insert new List<Form_Finding__c>{
            new Form_Finding__c(Linked_Form__c = lf.Id, Severity__c = 'Low',
                Status__c = 'Open', Notes__c = 'low'),
            new Form_Finding__c(Linked_Form__c = lf.Id, Severity__c = 'Medium',
                Status__c = 'Open', Notes__c = 'medium'),
            new Form_Finding__c(Linked_Form__c = lf.Id, Severity__c = 'Critical',
                Status__c = 'Open', Notes__c = 'critical')
        };

        NeuraFormPdfController.ReportData rd = NeuraFormPdfController.loadReportData(lf.Id);
        System.assertEquals(3, rd.findings.size());
        System.assertEquals('Critical', rd.findings[0].severity);
        System.assertEquals('Medium', rd.findings[1].severity,
            'Alphabetical ordering put Low above Medium.');
        System.assertEquals('Low', rd.findings[2].severity);
    }

    @isTest
    static void generatePdfIsIdempotentWithinWindow() {
        Form_Template__c tpl = new Form_Template__c(Name = 'T');
        insert tpl;
        Linked_Form__c lf = new Linked_Form__c(Form_Template__c = tpl.Id, Status__c = 'Completed');
        insert lf;

        Test.startTest();
        String first = NeuraFormPdfController.generatePdfForLinkedForm(lf.Id);
        String second = NeuraFormPdfController.generatePdfForLinkedForm(lf.Id);
        Test.stopTest();

        System.assertEquals(first, second,
            'A double-fired completion must reuse the just-generated PDF.');
        System.assertEquals(1, [
            SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :lf.Id
        ], 'Only one PDF should be attached to the form.');
    }
}
