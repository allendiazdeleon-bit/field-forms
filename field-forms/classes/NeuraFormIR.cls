/**
 * Canonical intermediate representation (IR) for form templates being
 * imported through the adapter framework. Every adapter
 * (NeuraFormFieldFormsAdapter, NeuraFormSteritechAdapter, future
 * customer-specific adapters) emits one of these, and
 * NeuraFormImporter is the single consumer. New customer formats become
 * new adapters; the importer never changes.
 *
 * Strongly-typed inner classes (rather than Map<String, Object>) give us
 * compile-time safety and let the adapter-to-importer hop work via
 * `JSON.deserialize(rawJson, NeuraFormIR.class)`. Trade-off: adding a
 * new IR field requires a class change, but the field count is small
 * and bounded by the design.
 *
 * IR version is tagged at the top level so we can support multiple
 * versions during a future migration (e.g. an adapter still emitting
 * 1.0 while the importer learns 1.1).
 *
 * Field names use snake_case to match the JSON shape documented in
 * docs/phase-2-pillar-3-adapter-framework.md. A few clashes with Apex
 * reserved words (`default`) are renamed (`default_value_*`); the
 * documented `order`, `operator`, `length`, `min`, `max` are all valid
 * Apex identifiers and used verbatim.
 *
 * See docs/phase-2-pillar-3-adapter-framework.md.
 */
public with sharing class NeuraFormIR {

    /** Default version tag emitted by v1 adapters. */
    public static final String CURRENT_VERSION = '1.0';

    public String ir_version;
    public Template template;
    public List<CatalogEntry> catalog_entries;
    public List<IRPage> pages;
    public List<Section> sections;
    public List<Binding> bindings;

    public NeuraFormIR() {
        this.ir_version = CURRENT_VERSION;
        this.catalog_entries = new List<CatalogEntry>();
        this.pages = new List<IRPage>();
        this.sections = new List<Section>();
        this.bindings = new List<Binding>();
    }

    /**
     * Top-level template metadata. Mirrors the small subset of
     * Form_Template__c fields the importer can populate from adapter
     * output. Anything not present (e.g. display preferences customers
     * set in the builder later) stays at its default.
     */
    public class Template {
        public String external_ref;
        public String name;
        public String indicator_type;
        public String selector_color;
    }

    /**
     * One row in the Form_Question_Catalog__c table — the question as an
     * asset, separate from where it appears. The same catalog entry can
     * be referenced by multiple bindings (Steritech's 60x-reused
     * question is one entry pointed at by 60 bindings).
     *
     * Numeric / validation knobs are null when an adapter doesn't
     * provide them — importer leaves the corresponding catalog field
     * unset rather than writing a synthetic zero.
     */
    public class CatalogEntry {
        public String external_ref;
        public String question_text;
        public String type;
        public String value_set;
        public Boolean required;
        public List<String> tags;
        public Decimal length;
        public Decimal min;
        public Decimal max;
        public Decimal decimal_places;
        public String slider_size;
        public Decimal slider_step;
        public String default_value_source;
        public String default_value_static;
        public String calculation_formula;
        public String calculation_result_format;
        public String date_time_save_format;
        public String active_message;
        public String inactive_message;
        public String display_rich_text;
        public Boolean include_comment;
        public Boolean include_photo;
        public Boolean label_visible;
        public String text_alignment;
        public String font_size;
        public String font_color;
        public String lookup_child_object;
        public String lookup_display_field;
        public String lookup_related_list;
    }

    /**
     * A logical grouping of sections inside the template. Pages have an
     * order and a title; section.page_ref binds sections to pages by
     * external_ref.
     */
    // Inner class renamed to IRPage because Apex reserves the identifier
    // `Page` (Visualforce). External Adapters / IR JSON consumers still
    // see the IR field as `pages` so the wire shape is unchanged.
    public class IRPage {
        public String external_ref;
        public String title;
        public Decimal order;
    }

    /**
     * A section within a page. `policy_text` lands as a first-class
     * Form_Section__c.Policy_Text__c field (added in this wave); it
     * houses Steritech-style per-section guidance and is null for
     * adapters that don't need it.
     */
    public class Section {
        public String external_ref;
        public String page_ref;
        public String title;
        public Decimal order;
        public String policy_text;
        public String columns;
    }

    /**
     * A placement of a catalog entry inside a section. The conditional
     * branching shape is normalized across adapters (resource / operator
     * / value); the importer doesn't care which source format produced
     * it.
     *
     * Per-binding overrides ride alongside the placement so the model
     * matches what Pillar 2's `Override_Question__c` /
     * `Override_Required__c` already do for builder-edited templates.
     */
    public class Binding {
        public String external_ref;
        public String section_ref;
        public String catalog_ref;
        public Decimal order;
        public String column;
        public String override_question;
        public String override_required;
        public List<Condition> conditions;
    }

    /**
     * Normalized condition shape. Adapters translate whatever per-format
     * conditional syntax into this canonical triple. `resource` is the
     * catalog_ref of the question the condition reads; the importer
     * resolves it to a Form_Question__c Id during the second pass.
     *
     * `operator` collides with Apex's reserved word handling in some
     * contexts when used as a field name during deserialization — keep
     * it as a plain identifier here; Apex's case-insensitive resolution
     * makes it safe at the field level. If a future deserializer balks,
     * rename to `op` and update adapters together.
     */
    public class Condition {
        public String resource;
        public String operator;
        public String value;
    }
}
