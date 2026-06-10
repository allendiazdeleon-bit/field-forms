/**
 * @description Server side for the brand form-management hub (neuraFormBrandHub)
 *  that lives on the Account record page. Lets an onboarding admin stand up a
 *  brand's forms without engineering: list the templates in the brand's Scope
 *  partition, create a blank one, clone an existing one, stamp imported ones
 *  with the brand scope, and flip Draft<->Active.
 *
 *  Brand <-> forms linkage reuses the existing Scope__c partition key rather
 *  than a new junction/lookup. An Account carries Form_Scope__c (the partition
 *  key); Form_Template__c.Scope__c is stamped to match. Null Scope on a
 *  template = global (shared across brands). See Form_Question_Catalog__c.Scope__c
 *  for the original framing of the partitioning design.
 *
 *  Clone deliberately reuses neuraFormExportController (fetchTemplatesData ->
 *  importTemplatesAsNew) so the deep copy of pages/sections/questions/criteria
 *  stays in one place; this class only stamps Scope/Status/Name afterward.
 */
public with sharing class NeuraFormBrandController {

    private static final Set<String> ALLOWED_STATUSES = new Set<String>{
        'Draft', 'Active', 'Retired'
    };

    /**
     * The brand record + its scope partition key, for the hub header. Read via
     * Apex rather than lightning/uiRecordApi getRecord because this component
     * also uses NavigationMixin, and that combination trips an LWC compiler
     * false-positive (LWC1503) in this API version.
     */
    @AuraEnabled(cacheable=true)
    public static Account getBrandContext(Id accountId) {
        List<Account> accounts = [
            SELECT Id, Name, Form_Scope__c FROM Account WHERE Id = :accountId
        ];
        if (accounts.isEmpty()) {
            return null;
        }
        return (Account) Security.stripInaccessible(
            AccessType.READABLE, accounts
        ).getRecords()[0];
    }

    /**
     * Stamps the brand partition key onto the Account so the hub can start
     * managing this brand's forms. Returns the updated record.
     */
    @AuraEnabled
    public static Account setAccountScope(Id accountId, String scope) {
        if (accountId == null) {
            throw new AuraHandledException('An account is required.');
        }
        if (String.isBlank(scope)) {
            throw new AuraHandledException('A brand scope key is required.');
        }
        // Re-pointing Form_Scope__c moves the brand's whole form partition —
        // enforce field-level perms on the write, not just record access. An
        // explicit check (not stripInaccessible) because silently stripping
        // the ONLY field this method writes produces a success toast with no
        // effect — the user must see why nothing happened.
        if (!Schema.sObjectType.Account.fields.Form_Scope__c.isUpdateable()) {
            throw new AuraHandledException(
                'You don\'t have edit access to Account.Form Scope. Ask an admin ' +
                'to assign the "Field Forms Brand Hub" permission set.'
            );
        }
        Account acct = new Account(Id = accountId, Form_Scope__c = scope.trim());
        update acct;
        return acct;
    }

    /**
     * Templates belonging to this brand's scope partition, newest-edited first.
     * Used to render the hub's list. Returns empty when scope is blank rather
     * than leaking every global template into an un-onboarded brand.
     */
    @AuraEnabled(cacheable=true)
    public static List<Form_Template__c> listTemplatesForScope(String scope) {
        if (String.isBlank(scope)) {
            return new List<Form_Template__c>();
        }
        List<Form_Template__c> templates = [
            SELECT Id, Name, Status__c, Scope__c, Scoring_Enabled__c,
                   Max_Score__c, Pass_Threshold_Percent__c, LastModifiedDate
            FROM Form_Template__c
            WHERE Scope__c = :scope
            ORDER BY LastModifiedDate DESC
        ];
        return (List<Form_Template__c>) Security.stripInaccessible(
            AccessType.READABLE, templates
        ).getRecords();
    }

    /**
     * Candidates for "Clone from Template": templates already in this brand's
     * scope plus global (null scope) templates that any brand can seed from.
     * Excludes Retired so admins don't clone dead forms by accident.
     */
    @AuraEnabled(cacheable=true)
    public static List<Form_Template__c> listClonableTemplates(String scope) {
        List<Form_Template__c> templates = [
            SELECT Id, Name, Status__c, Scope__c
            FROM Form_Template__c
            WHERE (Scope__c = :scope OR Scope__c = null)
              AND Status__c != 'Retired'
            ORDER BY Scope__c NULLS LAST, Name ASC
        ];
        return (List<Form_Template__c>) Security.stripInaccessible(
            AccessType.READABLE, templates
        ).getRecords();
    }

    /**
     * Creates an empty Draft template in the brand's scope and returns it so
     * the hub can navigate straight into the builder on the new record.
     */
    @AuraEnabled
    public static Form_Template__c createBlankTemplate(String name, String scope) {
        if (String.isBlank(name)) {
            throw new AuraHandledException('A form name is required.');
        }
        Form_Template__c tpl = new Form_Template__c(
            Name = name.trim(),
            Scope__c = String.isBlank(scope) ? null : scope.trim(),
            Status__c = 'Draft'
        );
        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.CREATABLE, new List<Form_Template__c>{ tpl }
        );
        insert decision.getRecords();
        return (Form_Template__c) decision.getRecords()[0];
    }

    /**
     * Deep-clones sourceId into a new Draft template stamped with this brand's
     * scope, and returns it. Reuses the export/import deep-copy machinery so the
     * full page/section/question/criteria graph comes along.
     */
    @AuraEnabled
    public static Form_Template__c cloneTemplate(Id sourceId, String newName, String scope) {
        if (sourceId == null) {
            throw new AuraHandledException('A source template is required.');
        }
        String json = neuraFormExportController.fetchTemplatesData(
            new List<String>{ String.valueOf(sourceId) }
        );
        neuraFormExportController.ImportResult result =
            neuraFormExportController.importTemplatesAsNew(json);
        if (result == null || result.templates == null || result.templates.isEmpty()) {
            throw new AuraHandledException('Clone produced no template. Check the source form.');
        }
        Form_Template__c copy = result.templates[0];
        // Sparse update: `copy` is the in-memory record deserialized from the
        // export JSON. A full-record update would rewrite every exported
        // field — including the Questions_JSON_*__c snapshot fragments that
        // importTemplatesAsNew just rebuilt with the clone's own question
        // Ids — corrupting mobile rendering of the clone for large templates.
        Form_Template__c stamp = new Form_Template__c(
            Id = copy.Id,
            Scope__c = String.isBlank(scope) ? null : scope.trim(),
            Status__c = 'Draft'
        );
        if (String.isNotBlank(newName)) {
            stamp.Name = newName.trim();
        }
        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.UPDATABLE, new List<Form_Template__c>{ stamp }
        );
        update decision.getRecords();
        copy.Scope__c = stamp.Scope__c;
        copy.Status__c = stamp.Status__c;
        if (String.isNotBlank(newName)) copy.Name = stamp.Name;
        return copy;
    }

    /**
     * Stamps the brand scope onto templates that were just brought in through
     * the JSON import flow (neuraFormImport returns the created Ids). Imported
     * templates default to Draft so they aren't synced to mobile until the
     * admin reviews and activates them.
     */
    @AuraEnabled
    public static void assignScope(List<Id> templateIds, String scope) {
        if (templateIds == null || templateIds.isEmpty()) {
            return;
        }
        List<Form_Template__c> toUpdate = [
            SELECT Id, Scope__c, Status__c
            FROM Form_Template__c
            WHERE Id IN :templateIds
        ];
        for (Form_Template__c tpl : toUpdate) {
            tpl.Scope__c = String.isBlank(scope) ? null : scope.trim();
            if (String.isBlank(tpl.Status__c)) {
                tpl.Status__c = 'Draft';
            }
        }
        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.UPDATABLE, toUpdate
        );
        update decision.getRecords();
    }

    // ----- Work Type assignments (Default_Form__c) --------------------------
    // "Make this form always appear on X jobs" — surfaced from the brand hub
    // and the builder's Form panel so admins never need the raw mapping
    // object's tab.

    public class WorkTypeAssignment {
        @AuraEnabled public Id defaultFormId;
        @AuraEnabled public Id workTypeId;
        @AuraEnabled public String workTypeName;
    }

    @AuraEnabled(cacheable=false)
    public static List<WorkTypeAssignment> getWorkTypeAssignments(Id formTemplateId) {
        List<WorkTypeAssignment> out = new List<WorkTypeAssignment>();
        if (formTemplateId == null) return out;
        for (Default_Form__c df : [
            SELECT Id, Work_Type__c, Work_Type__r.Name
            FROM Default_Form__c
            WHERE Form_Template__c = :formTemplateId
            WITH SECURITY_ENFORCED
            ORDER BY Work_Type__r.Name ASC
        ]) {
            WorkTypeAssignment a = new WorkTypeAssignment();
            a.defaultFormId = df.Id;
            a.workTypeId = df.Work_Type__c;
            a.workTypeName = df.Work_Type__r.Name;
            out.add(a);
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<WorkTypeAssignment> searchWorkTypes(String searchTerm) {
        String term = '%' + (searchTerm == null ? '' : String.escapeSingleQuotes(searchTerm)) + '%';
        List<WorkTypeAssignment> out = new List<WorkTypeAssignment>();
        for (WorkType wt : [
            SELECT Id, Name FROM WorkType
            WHERE Name LIKE :term
            WITH SECURITY_ENFORCED
            ORDER BY Name ASC
            LIMIT 15
        ]) {
            WorkTypeAssignment a = new WorkTypeAssignment();
            a.workTypeId = wt.Id;
            a.workTypeName = wt.Name;
            out.add(a);
        }
        return out;
    }

    /** Idempotent: assigning an already-mapped work type returns the
     *  existing row instead of duplicating the provisioning. */
    @AuraEnabled
    public static WorkTypeAssignment assignWorkType(Id formTemplateId, Id workTypeId) {
        if (formTemplateId == null || workTypeId == null) {
            throw new AuraHandledException('A form template and a work type are required.');
        }
        try {
            List<Default_Form__c> existing = [
                SELECT Id, Work_Type__r.Name FROM Default_Form__c
                WHERE Form_Template__c = :formTemplateId AND Work_Type__c = :workTypeId
                LIMIT 1
            ];
            Default_Form__c df;
            if (!existing.isEmpty()) {
                df = existing[0];
            } else {
                df = new Default_Form__c(
                    Form_Template__c = formTemplateId,
                    Work_Type__c = workTypeId
                );
                SObjectAccessDecision decision = Security.stripInaccessible(
                    AccessType.CREATABLE, new List<Default_Form__c>{ df }
                );
                insert decision.getRecords();
                df = [
                    SELECT Id, Work_Type__r.Name FROM Default_Form__c
                    WHERE Id = :decision.getRecords()[0].Id
                ];
            }
            WorkTypeAssignment a = new WorkTypeAssignment();
            a.defaultFormId = df.Id;
            a.workTypeId = workTypeId;
            a.workTypeName = df.Work_Type__r.Name;
            return a;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    @AuraEnabled
    public static void removeWorkTypeAssignment(Id defaultFormId) {
        if (defaultFormId == null) return;
        try {
            if (!Schema.sObjectType.Default_Form__c.isDeletable()) {
                throw new AuraHandledException('You don\'t have permission to remove form assignments.');
            }
            delete [SELECT Id FROM Default_Form__c WHERE Id = :defaultFormId];
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    /**
     * Flips a template's lifecycle status (Draft <-> Active, or Retired).
     * Restricted to the known value set so a bad client call can't write junk.
     */
    @AuraEnabled
    public static Form_Template__c setTemplateStatus(Id templateId, String status) {
        if (templateId == null) {
            throw new AuraHandledException('A template is required.');
        }
        if (!ALLOWED_STATUSES.contains(status)) {
            throw new AuraHandledException('Unknown status: ' + status);
        }
        Form_Template__c tpl = new Form_Template__c(Id = templateId, Status__c = status);
        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.UPDATABLE, new List<Form_Template__c>{ tpl }
        );
        update decision.getRecords();
        return tpl;
    }
}
