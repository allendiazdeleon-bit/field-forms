/**
 * Adapter contract: turn a customer-specific source format into the
 * canonical NeuraFormIR. The shared NeuraFormImporter is the single
 * consumer of IR; adapters are the only place where format-specific
 * logic lives.
 *
 * The interface intentionally stays tiny:
 *   - parse: do the work, return an IR (or throw)
 *   - label: a stable display name for the import UI
 *   - canHandle: an optional confidence score for auto-pick
 *
 * Initial adapter set (in this package):
 *   - NeuraFormFieldFormsAdapter — the existing exporter shape, so
 *     existing import flows keep working through the new pipeline.
 *   - NeuraFormSteritechAdapter — deferred; lands in a later wave.
 *
 * See docs/phase-2-pillar-3-adapter-framework.md.
 */
public interface NeuraFormSourceAdapter {

    /**
     * Parse a raw source string (JSON, XML, CSV — adapter's choice) into
     * the canonical IR. Adapters throw NeuraFormImporter.AdapterException
     * with a customer-readable message on parse failure; callers (the
     * importer UI) surface the message directly.
     *
     * The `options` map carries adapter-specific knobs (e.g. Steritech's
     * page-bucket overrides) without complicating the public surface.
     * Adapters that don't take options just ignore it.
     */
    NeuraFormIR parse(String source, Map<String, String> options);

    /**
     * Stable, human-readable name for this adapter. Surfaced verbatim in
     * the import UI's adapter picker.
     */
    String label();

    /**
     * Optional auto-detect: confidence score 0.0–1.0 indicating how
     * likely the adapter is to handle the given source. Used by the
     * import UI to auto-pick when one adapter scores high enough; admin
     * picks manually for ambiguous cases. Returning 0 (never match) or
     * 1 (always handle) are both fine; the contract just requires a
     * value in [0, 1].
     */
    Decimal canHandle(String source);
}
