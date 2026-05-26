# Phase 2 — Pillar 3: Adapter Framework

**Status:** Draft for review
**Scope:** Phase 2 of the Enterprise Readiness initiative
**Decides:** How customer-specific form-source formats become Form_Templates
**Companion docs:** Pillar 2 (Question Catalog), [snapshot-v2.md](snapshot-v2.md)
**Depends on:** Pillar 2 (catalog model exists)

## Why

Every enterprise customer arrives with their own form definition
format. Steritech ships a JSON file with `line_item_code` / nested
`child_question`. The HVAC template uses our own wrapper shape. Future
customers will bring more variations (XML, CSV, spreadsheet exports,
proprietary inspection-platform exports).

Today the path looks like:

- The existing importer (`NeuraFormExportController.importTemplates`)
  hard-codes one shape: the `FormTemplateWrapper` JSON that the export
  controller produces.
- Anything else becomes a per-customer Apex method or a one-off
  conversion script run by an engineer.

That doesn't scale to the next 10 customers. Worse, customers' own
identifiers (`line_item_code`, asset numbers, etc.) get lost at the
boundary because there's no canonical place to preserve them.

## Design

Three pieces: a canonical IR, a small Adapter interface, a single
shared importer.

### Canonical Intermediate Representation (IR)

A JSON shape every adapter produces. The importer only ever consumes
the IR. New customer formats become new adapters; the importer never
changes.

```jsonc
{
  "ir_version": "1.0",
  "template": {
    "external_ref": "STERITECH_INSP_2026Q2",
    "name": "Steritech Operational Excellence Audit (2026 Q2)",
    "indicator_type": "PASS_FAIL",
    "selector_color": "blue"
  },
  "catalog_entries": [
    {
      "external_ref": "b2b96b4b-2436-4a76-b20a-479c1b9d81b9",
      "question_text": "What did you observe?",
      "type": "Multiple Choice",
      "value_set": [
        { "id": "opt-1", "label": "PCO was verified, service reports are available", "value": "verified" },
        { "id": "opt-2", "label": "PCO could not be verified, no reports available", "value": "unverified" }
      ],
      "required": true,
      "tags": ["pest_prevention", "steritech_700"]
    }
    // ... one entry per unique question_id in the source ...
  ],
  "pages": [
    {
      "external_ref": "page-pest-prevention",
      "title": "Pest Prevention",
      "order": 1
    }
  ],
  "sections": [
    {
      "external_ref": "STERITECH_700",
      "page_ref": "page-pest-prevention",
      "title": "Pest prevention information",
      "order": 1,
      "policy_text": "Assessment Instructions: Document the name of the pest prevention service provider..."
    }
  ],
  "bindings": [
    {
      "external_ref": "binding-700-q1",
      "section_ref": "STERITECH_700",
      "catalog_ref": "b2b96b4b-2436-4a76-b20a-479c1b9d81b9",
      "order": 1,
      "column": "1",
      "conditions": []
    },
    {
      "external_ref": "binding-700-q2-conditional",
      "section_ref": "STERITECH_700",
      "catalog_ref": "c74dbbca-a3f8-4d48-b00a-6293e04b1f63",
      "order": 2,
      "column": "1",
      "conditions": [
        { "resource": "b2b96b4b-...", "operator": "equals", "value": "verified" }
      ]
    }
    // ... 2,265 bindings for Steritech, sharing 1,272 catalog refs ...
  ]
}
```

Notable IR properties:

- **External refs everywhere.** Every entity has an `external_ref` that
  the importer uses for upsert keying. Re-importing the same file
  updates existing records instead of duplicating them.
- **Catalog refs are first-class.** Sharing a question across bindings
  is the natural shape. Pillar 2 builds the underlying model.
- **Conditions are normalized.** Every adapter produces the same
  condition syntax (`resource` / `operator` / `value`); the importer
  doesn't care which source format it came from.
- **Policy text on sections.** Steritech's per-section guidance has a
  first-class slot. HVAC and others can leave it null. Renderer
  surfaces it as a section header / help panel.
- **No nesting of child questions.** Conditional branching is
  flattened: deeper-level questions become siblings with `conditions`
  pointing at the parent's answer.

### Adapter interface

```apex
public interface NeuraFormSourceAdapter {
    /**
     * Parse a raw source string (JSON, XML, CSV, whatever) into the
     * canonical IR. Throws AdapterException with a customer-readable
     * message on parse failure.
     */
    NeuraFormIR parse(String source, Map<String, String> options);

    /**
     * Stable name for this adapter, surfaced in the import UI.
     */
    String label();

    /**
     * Optional: detect whether this adapter can handle the given
     * source. Used by the import UI to auto-pick the adapter.
     * Return value is a confidence score 0.0-1.0.
     */
    Decimal canHandle(String source);
}
```

`NeuraFormIR` is a thin Apex wrapper around the IR shape (Apex inner
classes or `Map<String, Object>` — see Decisions below).

Initial adapter set:

- `NeuraFormFieldFormsAdapter` — consumes the existing exporter's
  shape. Replaces today's `importTemplates` hard-coded path.
- `NeuraFormSteritechAdapter` — consumes the Steritech JSON shape.
  Handles the flattening, type inference, and catalog dedupe.
- (future) `NeuraFormHvacAdapter`, `NeuraFormCustomerXAdapter`, etc.

### Shared importer

```apex
public class NeuraFormImporter {
    public static ImportResult import(NeuraFormIR ir) {
        // 1. Upsert template (by external_ref)
        // 2. Upsert catalog entries (by external_ref)
        // 3. Upsert pages (by external_ref)
        // 4. Upsert sections (by external_ref, link to pages)
        // 5. Upsert bindings (by external_ref, link to sections + catalog)
        // 6. Snapshot rebuild triggered by binding DML (existing pipeline)
        // 7. Return counts, warnings, errors
    }
}
```

One code path for every adapter. External-ref-keyed upserts make
re-imports idempotent and incremental: editing one section in the
source and re-importing updates only that section's records.

### Steritech adapter specifics

The bulk of "adapter work" for Steritech is in this one class:

1. **Flatten recursive `child_question`.** Walk each top-level
   question; for each option that has a `child_question`, emit a
   sibling binding with a `conditions` entry referencing the parent's
   answer. Recurse to arbitrary depth. Map nesting depth to `order`
   within the section so flat siblings stay in their original tree
   order.

2. **Dedupe by `question_id`.** The 60×-reused question becomes one
   catalog entry referenced by 60 bindings. Each binding carries the
   conditions that triggered it.

3. **Type inference from question text.** Heuristics:
   - "Enter the date..." → Date
   - "Briefly describe..." / "Describe..." / "Provide additional details..." → Text Area
   - "Enter the name..." / "Enter the..." (non-date) → Text
   - "Select the..." / "What was..." / "Which..." (with options) → Multiple Choice / Radio Buttons
   - "What was the final cooking temperature..." → Number
   - Default with options → Multiple Choice
   - Default without options → Text

   Emit a `warnings` entry for every inferred type so the admin can
   review.

4. **Sections from `line_item_code`.** Each top-level Steritech line
   item becomes a Form_Section with `external_ref` = the
   `line_item_code`. Preserves the customer's taxonomy through to
   export.

5. **Pages from prefix grouping.** Bucket sections by `line_item_code`
   prefix (`A`, `B`, `C`, `7`, etc.) into 5-10 logical pages. Bucket
   mapping is a small constant table; admins can override after import.

6. **Policy text into `section.policy_text`.** Already a first-class
   IR field; renderer decides how to surface (collapsible help panel
   recommended).

## Import UI flow

1. Admin uploads a file.
2. System runs `canHandle` on each registered adapter; picks the
   highest-confidence (or admin picks if tied / under threshold).
3. Adapter parses → IR.
4. Importer runs a **dry-run** first: produces counts (X templates,
   Y catalog entries, Z bindings) + warnings (type inferences, missing
   external_refs, ambiguous mappings).
5. Admin reviews dry-run output, can cancel or proceed.
6. Importer runs for real, returns ImportResult.

The dry-run / preview is the same one the existing
`NeuraFormExportController.previewImport` builds; route it through the
new adapter pipeline.

## Backward compatibility

The existing exporter shape (`FormTemplateWrapper`) becomes one
adapter (`NeuraFormFieldFormsAdapter`) among several. The existing
`importTemplates` entry point stays as a thin wrapper that:
1. Wraps the JSON in `NeuraFormFieldFormsAdapter`,
2. Calls `NeuraFormImporter.import`,
3. Returns the same `ImportResult` shape it always did.

Existing import flows keep working. New flows (Steritech, others) go
through the same plumbing.

## Risks

| Risk | Mitigation |
|---|---|
| IR design locks us in | Version the IR (`ir_version: "1.0"`); old adapters declare which IR version they emit; the importer can support multiple versions briefly during a migration |
| Steritech type inference produces wrong types | Inferred types always come with warnings; admin reviews and corrects in builder. Track inference accuracy across imports as a metric. |
| Adapter selection ambiguity (two adapters say "I can handle this") | UI prompts admin to pick when confidence scores are tied. Log adapter choices for observability. |
| Re-import overwrites admin's manual edits | External-ref upsert means re-import is *destructive* for fields covered by the source. Document this. Future: "merge mode" that preserves admin overrides. |
| Adapter for a one-off customer ships in core | Adapters could live in a separate package or as managed-package extensions. v1: ship in core; if it becomes a noise problem, split into an "adapters" managed package. |
| IR JSON size for large customers (Steritech IR is multi-MB) | IR is in-memory only during import; never stored. Heap is the concern. Stream large imports through batch chunks if needed. |

## Decisions

| Decision | Choice | Reason |
|---|---|---|
| IR representation in Apex | Strongly-typed inner classes on `NeuraFormIR` | Compile-time safety beats Map<String, Object> guesswork; small Apex serializer round-trip cost is fine |
| Adapter discovery | Custom metadata type `NeuraForm_Adapter__mdt` lists registered adapters | Admins can disable / reorder without code changes |
| Adapter selection in UI | Auto-pick when one adapter scores > 0.8 confidence; else show picker | Removes friction for known formats; preserves control for ambiguous ones |
| Import mode | Dry-run mandatory before write | Catches Steritech-class surprises before customer DML; admins get an audit trail |
| Re-import semantics | Destructive upsert (source is authoritative) | Predictable. Admins who want to preserve manual edits clone the template before re-import. |
| Where adapters live | In core (`field-forms` package) for v1 | Single deploy story. Split into adapters package only if it becomes large enough to matter. |
| Existing importer | Becomes `NeuraFormFieldFormsAdapter` | Zero breakage; new path exercised by existing tests |

## Open questions

1. **Should `policy_text` be a section field or a synthetic
   Display-Text question?** Phase 1's mapping had it as a question.
   Cleaner as a first-class field. Lean: first-class field on
   Form_Section__c (`Help_Text__c` / `Policy_Text__c`). Renderer
   decision is downstream.
2. **CSV / spreadsheet adapters** — common ask. Not in v1, but the
   adapter interface supports it. Defer until a customer asks.
3. **Adapter versioning across managed-package upgrades** — adapter
   classes need to handle IR version bumps gracefully. Document the
   contract; not enforced by code in v1.
4. **Should we expose IR as a public API?** Customers could integrate
   their backend directly without writing an adapter. Defer to Phase
   3's API surface work.

## Estimated effort

- IR shape + Apex types: 0.5d
- Adapter interface + custom metadata for registry: 0.5d
- `NeuraFormImporter` (shared core, IR-driven upsert): 2d
- `NeuraFormFieldFormsAdapter` (refactor of existing import): 1d
- `NeuraFormSteritechAdapter` (the actual lift): 3d
  - Flatten recursion: 0.5d
  - Type inference + warnings: 0.5d
  - Section / page mapping: 0.5d
  - Catalog dedupe by question_id: 0.5d
  - Tests: 1d
- Importer UI updates (dry-run preview, adapter picker): 2d
- Integration + smoke test against real `steritech.json`: 1d
- Buffer: 1d

**~11 dev-days end-to-end.** The Steritech adapter is the chunkiest
single piece because it's where the messy customer-specific logic
lives. Future adapters are smaller (~3d each).

## Sequencing within Pillar 3

1. IR shape + adapter interface + registry metadata
2. `NeuraFormImporter` (shared core)
3. `NeuraFormFieldFormsAdapter` (smoke: existing imports keep working)
4. `NeuraFormSteritechAdapter` + tests
5. Importer UI updates (dry-run, adapter picker)
6. Real `steritech.json` end-to-end test against afcc_apr26

Cut points: land 1-3 as one wave (existing imports working through new
plumbing); 4-6 as a second wave (Steritech onboarded).
