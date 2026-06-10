/**
 * Blocks a second ACTIVE Brand_Theme__c at the same resolution tier — the
 * same (Scope__c, Form_Template__c) pair, where null template = brand level
 * and null both = the org-global theme.
 *
 * NeuraFormBrandThemeController.resolve() picks deterministically (newest
 * wins) when duplicates exist, but a silent winner is still an authoring
 * trap: an admin edits the loser and nothing changes on the rendered PDF.
 * Better to stop the ambiguity at save time with an actionable error.
 */
trigger BrandThemeTrigger on Brand_Theme__c (before insert, before update) {
    List<Brand_Theme__c> activating = new List<Brand_Theme__c>();
    for (Brand_Theme__c theme : Trigger.new) {
        if (theme.Active__c == true) activating.add(theme);
    }
    if (activating.isEmpty()) return;

    Set<String> scopes = new Set<String>();
    Set<Id> templateIds = new Set<Id>();
    for (Brand_Theme__c theme : activating) {
        if (theme.Scope__c != null) scopes.add(theme.Scope__c);
        if (theme.Form_Template__c != null) templateIds.add(theme.Form_Template__c);
    }

    Map<String, Brand_Theme__c> activeByTier = new Map<String, Brand_Theme__c>();
    for (Brand_Theme__c existing : [
        SELECT Id, Name, Scope__c, Form_Template__c
        FROM Brand_Theme__c
        WHERE Active__c = true
          AND (Scope__c IN :scopes OR Form_Template__c IN :templateIds
               OR (Scope__c = null AND Form_Template__c = null))
    ]) {
        activeByTier.put(existing.Scope__c + '|' + existing.Form_Template__c, existing);
    }

    for (Brand_Theme__c theme : activating) {
        String tier = theme.Scope__c + '|' + theme.Form_Template__c;
        Brand_Theme__c clash = activeByTier.get(tier);
        if (clash != null && clash.Id != theme.Id) {
            String where_ = theme.Form_Template__c != null
                ? 'this form template'
                : (theme.Scope__c != null ? 'scope "' + theme.Scope__c + '"' : 'the org default');
            theme.addError(
                'An active theme already exists for ' + where_ + ' ("' + clash.Name +
                '"). Deactivate it first, or edit it instead — two active themes at the ' +
                'same level make the rendered branding ambiguous.'
            );
        } else {
            // Within this same save: two rows activating into one tier.
            activeByTier.put(tier, theme);
        }
    }
}
