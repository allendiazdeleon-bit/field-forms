/**
 * Resolves the Brand_Theme__c that applies to a form or inspection (Vignette 4).
 *
 * One theme layer, two consumers: the live form renderer (injects the colors
 * as CSS custom properties) and the branded PDF report. Resolution is
 * most-specific-first:
 *   1. FORM-level   - Brand_Theme__c with Form_Template__c = this template
 *   2. BRAND-level  - Brand_Theme__c with Scope__c = this brand, no template
 *   3. GLOBAL       - Brand_Theme__c with neither set (the org default)
 *   4. Hardcoded fallback (the stock Neura palette) so a consumer can always
 *      apply a theme without null-checking.
 *
 * Keyed by the same Scope__c partition used everywhere else (Account.Form_Scope__c
 * -> Form_Template__c.Scope__c), so branding rides the existing brand spine.
 */
public with sharing class NeuraFormBrandThemeController {

    // Stock palette - matches the static design-system tokens so an un-themed
    // org looks exactly as it does today. Public: NeuraFormPdfController seeds
    // its ReportData with these so a missing/invalid theme can never leave a
    // null color in the rendered CSS.
    public static final String DEFAULT_PRIMARY = '#0070d2';
    public static final String DEFAULT_SECONDARY = '#1589ee';

    public class Theme {
        @AuraEnabled public String primaryColor;
        @AuraEnabled public String secondaryColor;
        @AuraEnabled public String logoUrl;
        @AuraEnabled public String headerText;
        @AuraEnabled public String sectionOrder;   // raw JSON, consumer parses
        @AuraEnabled public String locale;
        @AuraEnabled public String outputTemplateHtml; // HTML template (merge tokens) or null
        @AuraEnabled public String source;          // 'form' | 'brand' | 'global' | 'default'
        @AuraEnabled public Id themeId;
    }

    /**
     * Resolve for the live renderer / builder, which knows the template.
     */
    @AuraEnabled(cacheable=true)
    public static Theme getThemeForTemplate(Id formTemplateId) {
        String scope = null;
        if (formTemplateId != null) {
            List<Form_Template__c> t = [
                SELECT Scope__c FROM Form_Template__c WHERE Id = :formTemplateId LIMIT 1
            ];
            if (!t.isEmpty()) scope = t[0].Scope__c;
        }
        return resolve(formTemplateId, scope);
    }

    /**
     * Resolve for the report generator, which has a completed inspection.
     * Brand scope comes from the Account on the Linked Form.
     */
    @AuraEnabled(cacheable=true)
    public static Theme getThemeForLinkedForm(Id linkedFormId) {
        if (linkedFormId == null) return resolve(null, null);
        List<Linked_Form__c> lf = [
            SELECT Form_Template__c, Account__r.Form_Scope__c, Form_Template__r.Scope__c
            FROM Linked_Form__c WHERE Id = :linkedFormId LIMIT 1
        ];
        if (lf.isEmpty()) return resolve(null, null);
        // Prefer the Account's brand scope; fall back to the template's own scope.
        String scope = lf[0].Account__r != null ? lf[0].Account__r.Form_Scope__c : null;
        if (String.isBlank(scope)) scope = lf[0].Form_Template__r != null ? lf[0].Form_Template__r.Scope__c : null;
        return resolve(lf[0].Form_Template__c, scope);
    }

    /**
     * For callers that already hold the template Id + scope (e.g. the PDF
     * controller, which has the Linked_Form loaded) — skips the extra
     * Linked_Form__c query that getThemeForLinkedForm would repeat.
     */
    public static Theme resolveTheme(Id formTemplateId, String scope) {
        return resolve(formTemplateId, scope);
    }

    /**
     * Core resolver. Public+TestVisible so both entry points and tests share it.
     */
    @TestVisible
    private static Theme resolve(Id formTemplateId, String scope) {
        // Over-fetch the candidate themes (form match, brand-scope match, or
        // global) and pick the most specific in Apex - SOQL can't express the
        // "bind is null" guards inline. Nothing enforces uniqueness per tier,
        // so order newest-first and keep the FIRST match per tier — the
        // winner is deterministic (latest edit) instead of query-order luck.
        List<Brand_Theme__c> themes = [
            SELECT Id, Scope__c, Form_Template__c, Primary_Color__c, Secondary_Color__c,
                   Logo_URL__c, Header_Text__c, Section_Order__c, Locale__c,
                   Output_Template_Html__c
            FROM Brand_Theme__c
            WHERE Active__c = true
              AND (
                Form_Template__c = :formTemplateId
                OR Scope__c = :scope
                OR (Scope__c = null AND Form_Template__c = null)
              )
            ORDER BY LastModifiedDate DESC, Id DESC
        ];

        Brand_Theme__c formMatch, brandMatch, globalMatch;
        for (Brand_Theme__c bt : themes) {
            if (formTemplateId != null && bt.Form_Template__c == formTemplateId) {
                if (formMatch == null) formMatch = bt;
            } else if (String.isNotBlank(scope) && bt.Scope__c == scope && bt.Form_Template__c == null) {
                if (brandMatch == null) brandMatch = bt;
            } else if (bt.Scope__c == null && bt.Form_Template__c == null) {
                if (globalMatch == null) globalMatch = bt;
            }
        }

        if (formMatch != null) return toTheme(formMatch, 'form');
        if (brandMatch != null) return toTheme(brandMatch, 'brand');
        if (globalMatch != null) return toTheme(globalMatch, 'global');
        return stockTheme();
    }

    private static Theme toTheme(Brand_Theme__c bt, String source) {
        Theme t = new Theme();
        t.themeId = bt.Id;
        t.source = source;
        // Colors are free-text fields that land inside a VF <style> block and
        // inline styles — HTML-escaping doesn't help in CSS context, so only
        // a strict hex shape passes; anything else falls back to stock.
        t.primaryColor = validColorOr(bt.Primary_Color__c, DEFAULT_PRIMARY);
        t.secondaryColor = validColorOr(bt.Secondary_Color__c, DEFAULT_SECONDARY);
        // The logo URL is concatenated into <img src> by consumers; require a
        // web scheme so javascript:/data: (or attribute breakouts upstream of
        // escaping) never reach the document.
        t.logoUrl = validLogoUrl(bt.Logo_URL__c);
        t.headerText = bt.Header_Text__c;
        t.sectionOrder = bt.Section_Order__c;
        t.locale = bt.Locale__c;
        t.outputTemplateHtml = bt.Output_Template_Html__c;
        return t;
    }

    @TestVisible
    private static String validColorOr(String candidate, String fallback) {
        if (String.isBlank(candidate)) return fallback;
        return Pattern.matches('^#[0-9A-Fa-f]{3,8}$', candidate.trim())
            ? candidate.trim() : fallback;
    }

    @TestVisible
    private static String validLogoUrl(String url) {
        if (String.isBlank(url)) return null;
        String trimmed = url.trim();
        String lower = trimmed.toLowerCase();
        return (lower.startsWith('https://') || lower.startsWith('http://') || lower.startsWith('/'))
            ? trimmed : null;
    }

    private static Theme stockTheme() {
        Theme t = new Theme();
        t.source = 'default';
        t.primaryColor = DEFAULT_PRIMARY;
        t.secondaryColor = DEFAULT_SECONDARY;
        return t;
    }
}
