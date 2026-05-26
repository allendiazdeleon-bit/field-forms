/**
 * End-to-end import entry point that ties an adapter to the shared
 * NeuraFormImporter and the existing snapshot rebuild trigger pipeline.
 *
 * This is the surface the Aura-callable `importTemplates` controller
 * method delegates to: it takes a raw source string + an adapter label
 * (or auto-picks via canHandle), runs the adapter to produce IR per
 * template, runs the importer for each IR inside a single Savepoint,
 * and triggers a synchronous snapshot rebuild so the LWC doesn't have
 * to issue a follow-up call.
 *
 * Registry: v1 ships a constant map of adapter label → adapter instance.
 * The design doc names `NeuraForm_Adapter__mdt` as the future home but
 * marks it optional for v1 — small constant map is fine until a third
 * adapter ships.
 *
 * See docs/phase-2-pillar-3-adapter-framework.md.
 */
public with sharing class NeuraFormImportPipeline {

    /**
     * Adapter label used in the registry / UI for the existing Field
     * Forms native export shape. Stable across versions so re-imports
     * pick the same adapter.
     */
    public static final String LABEL_FIELD_FORMS = 'Field Forms (native export)';

    /**
     * Constant adapter registry. Replace with `NeuraForm_Adapter__mdt`
     * lookups once a third adapter ships (Steritech is queued as #2).
     */
    @TestVisible
    private static Map<String, NeuraFormSourceAdapter> registry() {
        return new Map<String, NeuraFormSourceAdapter>{
            LABEL_FIELD_FORMS => new NeuraFormFieldFormsAdapter()
        };
    }

    /**
     * Combined result shape for the LWC: per-template counts aggregated
     * across the whole import payload. Mirrors the legacy ImportResult
     * shape (templates / created / updated / warnings) so the existing
     * import LWC keeps working — see neuraFormExportController.ImportResult.
     */
    public class PipelineResult {
        @AuraEnabled public List<Form_Template__c> templates = new List<Form_Template__c>();
        @AuraEnabled public Integer createdCount = 0;
        @AuraEnabled public Integer updatedCount = 0;
        @AuraEnabled public List<String> warnings = new List<String>();
        @AuraEnabled public String adapterLabel;
    }

    /**
     * Auto-pick the adapter with the highest canHandle score. Returns
     * null when no adapter scores > 0 (caller falls back to the
     * Field-Forms default for backward compatibility with the existing
     * importTemplates entry point).
     */
    public static String pickAdapter(String source) {
        if (String.isBlank(source)) return null;
        String bestLabel = null;
        Decimal bestScore = 0;
        for (String label : registry().keySet()) {
            NeuraFormSourceAdapter a = registry().get(label);
            Decimal score = 0;
            try { score = a.canHandle(source); } catch (Exception e) { score = 0; }
            if (score != null && score > bestScore) {
                bestScore = score;
                bestLabel = label;
            }
        }
        return bestLabel;
    }

    /**
     * Run an import using the named adapter. `null` for adapterLabel
     * means "auto-pick"; if auto-pick fails, fall back to the
     * Field-Forms adapter so the existing import-from-export round trip
     * keeps working without admin intervention.
     */
    public static PipelineResult importSource(
        String source, String adapterLabel, Map<String, String> options
    ) {
        if (String.isBlank(source)) {
            throw new NeuraFormImporter.AdapterException('Empty source payload.');
        }
        String chosen = adapterLabel;
        if (String.isBlank(chosen)) chosen = pickAdapter(source);
        if (String.isBlank(chosen)) chosen = LABEL_FIELD_FORMS;
        NeuraFormSourceAdapter adapter = registry().get(chosen);
        if (adapter == null) {
            throw new NeuraFormImporter.AdapterException(
                'No adapter registered for label: ' + chosen
            );
        }

        PipelineResult result = new PipelineResult();
        result.adapterLabel = chosen;
        Savepoint sp = Database.setSavepoint();
        try {
            // Existing import shape packs N templates per file (List of
            // wrappers). We honor that by iterating the JSON array and
            // running the adapter per wrapper. Adapters that own their
            // own multi-template format (Steritech ships one template
            // per file) can ignore the loop in their canHandle/parse.
            List<Map<String, Object>> wrappers = peelWrappers(source);
            if (wrappers.isEmpty()) {
                // Adapter parses the whole source as-is (single-template
                // formats). Single pass.
                runOne(adapter.parse(source, options), result);
            } else {
                NeuraFormFieldFormsAdapter ffAdapter =
                    (adapter instanceof NeuraFormFieldFormsAdapter)
                        ? (NeuraFormFieldFormsAdapter) adapter : null;
                for (Map<String, Object> wrapper : wrappers) {
                    NeuraFormIR ir = (ffAdapter != null)
                        ? ffAdapter.parseWrapper(wrapper)
                        : adapter.parse(JSON.serialize(wrapper), options);
                    runOne(ir, result);
                }
            }

            // Trigger synchronous snapshot rebuild so the new templates
            // render immediately. Mirrors the existing importTemplates
            // behavior — the trigger pipeline may also enqueue an async
            // rebuild, harmless duplicate.
            Set<Id> templateIds = new Set<Id>();
            for (Form_Template__c t : result.templates) templateIds.add(t.Id);
            if (!templateIds.isEmpty()) {
                NeuraFormLogic.processTemplates(templateIds);
            }
            return result;
        } catch (Exception e) {
            Database.rollback(sp);
            throw e;
        }
    }

    /**
     * Run one IR through the shared importer and roll its counts into
     * the per-payload result.
     */
    private static void runOne(NeuraFormIR ir, PipelineResult result) {
        NeuraFormImporter.ImportResult r = NeuraFormImporter.runImport(ir);
        if (r.templateId != null) {
            result.templates.add(new Form_Template__c(
                Id = r.templateId,
                External_Reference__c = r.templateExternalRef
            ));
        }
        result.createdCount += r.templatesCreated;
        result.updatedCount += r.templatesUpdated;
        if (r.warnings != null) result.warnings.addAll(r.warnings);
    }

    /**
     * Attempt to read the source as a JSON array of wrapper objects (the
     * Field Forms export shape). Returns an empty list when the source
     * isn't shaped that way — the caller falls back to single-pass
     * adapter.parse(source). Cheap untyped parse; the per-wrapper
     * adapter call does the real work.
     */
    private static List<Map<String, Object>> peelWrappers(String source) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        Object parsed;
        try { parsed = JSON.deserializeUntyped(source); } catch (Exception e) { return out; }
        if (!(parsed instanceof List<Object>)) return out;
        for (Object item : (List<Object>) parsed) {
            if (item instanceof Map<String, Object>) {
                Map<String, Object> m = (Map<String, Object>) item;
                // Smell-check: only treat as wrapper if it carries the
                // canonical top-level keys. Adapters with their own
                // shape (e.g. Steritech's `line_items` root) won't match
                // and the caller will hand the raw source to
                // adapter.parse().
                if (m.containsKey('template') && m.containsKey('pages')) {
                    out.add(m);
                }
            }
        }
        return out;
    }
}
