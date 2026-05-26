# Phase 2 — Pillar 2: Question Catalog

**Status:** Draft for review
**Scope:** Phase 2 of the Enterprise Readiness initiative
**Decides:** How questions are stored as reusable assets across templates
**Companion docs:** [snapshot-v2.md](snapshot-v2.md) (Phase 1), Pillar 3 (Adapter framework), Pillar 5 (Scoring + Findings)

## Why

`Form_Question__c` today couples *what a question is* (the question text,
type, options, validation rules) with *where it appears* (template, page,
section, order). Every appearance of a question is a fresh row even when
the content is identical.

The Steritech import is the clearest example: 1,272 unique `question_id`
values appear 2,265 times in the source. One of them appears **60×**.
With today's model we'd materialize 60 rows of "Enter the date of
service for the most recent report." Edits drift, cross-template
analytics are impossible, and there's no "is this on the SQF Level 3
list" certification surface.

The fix is to separate the asset from the placement.

## Design

### New SObject — `Form_Question_Catalog__c`

The canonical asset. All semantic / content fields move here:

```
Form_Question_Catalog__c
  External_Reference__c        Text(80), External Id, Unique
  Question__c                  LongTextArea(32768)
  Type__c                      Picklist (Form_Question_Answer_types)
  Value_Set__c                 LongTextArea(32768)
  Default_Value_Source__c      Picklist
  Default_Value_Static__c      Text
  Length__c                    Number
  Min__c / Max__c              Number
  Decimal_Places__c            Number
  Slider_Size__c / Step__c     Number
  Calculation_Formula__c       LongTextArea
  Calculation_Result_Format__c Picklist
  Date_Time_Save_Format__c     Picklist
  Active_Message__c            LongTextArea
  Inactive_Message__c          LongTextArea
  Display_Rich_Text__c         Checkbox
  Include_Comment__c           Checkbox
  Include_Photo__c             Checkbox
  Required__c                  Checkbox (default; overridable per binding)
  Label_Visible__c             Checkbox
  Text_Alignment__c            Picklist
  Font_Size__c / Font_Color__c Text
  Lookup_Child_Object__c       Text (for lookup-type questions)
  Lookup_Display_Field__c      Text
  Lookup_Related_List__c       Text
  Tags__c                      LongTextArea  (NEW — for cross-template filtering)
```

`Required__c` and a handful of presentation fields stay overridable per
binding (see below). Everything else lives at the catalog level.

### Refactored `Form_Question__c` — the binding

`Form_Question__c` becomes a placement record:

```
Form_Question__c (binding)
  Form_Template__c             Master-Detail → Form_Template__c       (unchanged)
  Form_Page__c                 Lookup        → Form_Page__c           (unchanged)
  Form_Section__c              Lookup        → Form_Section__c        (unchanged)
  Order__c                     Number                                  (unchanged)
  Column__c                    Text                                    (unchanged)
  Form_Question_Catalog__c     Lookup → Form_Question_Catalog__c       (NEW, required after migration)
  Conditions__c                LongTextArea                            (unchanged — branching is per-placement)
  Override_Question__c         LongTextArea  (NEW, nullable — per-binding question text override)
  Override_Required__c         Checkbox      (NEW, nullable proxy via a tristate text field)
  External_Reference__c        Text          (unchanged)
```

All content fields (`Question__c`, `Type__c`, `Value_Set__c`, etc.) are
**removed from Form_Question__c after migration completes** — readers
get them from the catalog.

#### Override scope (deliberately minimal in v1)

Only two overrides shipped in v1: `Override_Question__c` (rewrite the
displayed text) and `Override_Required__c` (toggle required per
binding). Everything else is catalog-level. If a template needs a
materially different question, fork the catalog entry — keeps the model
simple. Expand override set in v1.1 only if real customer demand
materializes.

### Conditions stay on the binding

Branching logic is *per-placement*, not catalog-wide: question Q might
be conditional on Q1 in template A and conditional on Q3 in template B.
`Conditions__c` therefore stays on `Form_Question__c`.

## Migration — catalog-of-one shim

Customers have existing data. Every `Form_Question__c` row needs a
catalog entry, and the schema flip cannot break running orgs.

### Strategy

1. **Phase a: schema deploy.** Ship `Form_Question_Catalog__c` and add
   the `Form_Question_Catalog__c` lookup field on `Form_Question__c`
   (nullable initially). No reads change yet.

2. **Phase b: backfill batch — `NeuraFormCatalogBackfillBatch`.** For
   each existing `Form_Question__c`:
   - Compute a content hash of (Question__c, Type__c, Value_Set__c, the
     other content fields)
   - If a catalog entry with that hash exists in this template's scope,
     bind to it
   - Else insert a new catalog entry, bind to it
   - `External_Reference__c` on the catalog: prefer the binding's
     existing External_Reference__c; fall back to a generated UUID

   This produces a 1:1 catalog-of-one in most cases (no auto-dedupe
   across templates by default — see "Decisions" below).

3. **Phase c: dual-read shim.** Update readers
   (`NeuraFormSnapshotV2`, builder controller, mobile / desktop) to
   resolve content fields through the binding's catalog reference first,
   falling back to the binding's own (legacy) content fields if the
   catalog reference is null. Snapshot writer caches resolved values
   into chunk payloads so the renderer is unchanged.

4. **Phase d: dual-write.** Builder/import paths write to *both* the
   binding (content fields) and the catalog. Customers can opt into
   "catalog-only" writes via a setting.

5. **Phase e: cutover.** After 2 minor releases of dual-read/dual-write,
   make the catalog reference required, deprecate the binding's content
   fields, then drop them in a future major release.

### Dedupe — separate user-driven step

Real dedupe (recognizing that two catalog entries are the *same* across
templates) is a UI workflow, not a migration step. The builder gains a
"merge catalog entries" action: admin picks two entries, picks a
canonical one, all bindings re-point, the loser is deleted. Out of v1
scope; documented as a Phase 2.1 followup.

## Read-path impact

| Reader | Change |
|---|---|
| `NeuraFormSnapshotV2.rebuild` | Query `Form_Question_Catalog__c` for each binding's catalog ref. Apply overrides. Emit the resolved values into Questions chunks. **All other readers unchanged because they consume the snapshot.** |
| Builder controller `getFormDetails` | Update query to include the catalog ref + selected catalog fields. Builder LWC gets a resolved question shape (catalog merged with overrides). |
| Exporter (`NeuraFormExportController`) | Decide whether export embeds catalog content (portable, larger) or catalog refs (smaller, requires catalog to exist on import target). Lean: embed for portability; importer dedupes on read. |
| Mobile (`NeuraFormMobileController.getMobileFormDetails`) | No change — reads snapshot. |
| Mobile briefcase | No change — snapshot rides briefcase. Catalog itself does *not* need to ride briefcase (snapshot has resolved values). |

The fact that snapshot writes are the only thing that resolves catalog
references means the read-side blast radius is small. This is a
deliberate consequence of Phase 1's snapshot architecture.

## Builder UI impact

Two new affordances:

1. **"Pick from catalog" when adding a question** — autocomplete by
   question text or `Tags__c`. Selects a catalog entry; creates a
   binding bound to it.
2. **"Edit catalog entry" link from any binding** — opens the catalog
   record; warns "this change affects N templates."

Existing "add question" flow still works: it creates a catalog entry
and a binding in one shot (the catalog-of-one default).

### The "fresh binding" problem (resolved)

Once "catalog-of-one default" is implemented, every new question in
the builder also produces a fresh catalog entry that has exactly one
binding. The Wave 35.7 read-only-when-inherited treatment was designed
for *shared* catalog entries (multiple bindings, edits would surprise
other templates). For a fresh binding with a fresh catalog entry,
forcing the admin through an "Override in this template" click before
they can type anything is friction.

**Resolution:** make the inherited-mode read-only treatment
**binding-count-aware**. When the catalog entry has only one binding
(this one), the question input remains editable and edits write
through to the catalog directly. Once a second binding points at the
same catalog entry (via "Pick from catalog" or programmatic linking),
the editing UX shifts to the shared/inherited treatment.

The controller (`getFormDetails`) includes the binding count per
catalog entry in its response so the LWC can compute this without an
extra round-trip.

## Operating at scale

Three concerns surface when multiple admins author concurrently or
when the org serves multiple downstream customers. Each is a layered
control rather than a single fix.

### Drift — near-duplicate catalog entries

Without intervention, the catalog turns into noise within months:

```
"Enter the date of last service"
"Enter date of last service"
"What was the date of last service?"
```

All mean the same thing; analytics, reuse, and scoring fragment.
**Three controls, deployed in layers:**

| Control | Surface | When it fires | v1 vs deferred |
|---|---|---|---|
| Type-ahead similarity at create | Builder add-question modal | Admin types question text → SOSL search the catalog → "Did you mean…?" hints | v1 — closes the loop at the boundary where drift starts |
| Mass-add staging UI | New surface | Power user pastes/uploads N candidate questions → each pre-matched against catalog → admin reviews and bulk-inserts only what's truly new | Deferred — Pillar 3 adapter framework also covers mass-add from external sources |
| Merge workflow | Catalog browser | Admin selects N near-duplicates → picks canonical → bindings re-point → losers deleted | Deferred — surgical cleanup, after-the-fact |

SOSL is the practical search engine in v1
(`FIND :userText IN ALL FIELDS RETURNING Form_Question_Catalog__c(Id, Question__c)`).
It's token-matching with stemming, already indexed, free. If the
platform ships vector search natively, swap to embeddings then.

### Customer scoping — cross-customer pollution

A service provider like Steritech audits many downstream customers
within their single Salesforce org. Some questions should be
universally reusable (brand standards, regulatory); others should
be partitioned per chain or geography. Editing a chain-A-scoped
question must not silently affect chain-B's templates.

**Decision: add `Scope__c` to `Form_Question_Catalog__c` now,
implement filtering soon, defer scope-management UX.**

- Field type: **Text(80)**. Customers populate with whatever scoping
  string makes sense for their data model ("steritech-default",
  "chain-A", "regulatory"). Zero migration cost.
- Default: **null = global/unscoped**, visible to all templates. All
  catalog entries created before this field's introduction default
  to null and remain visible everywhere.
- Filtering: `Form_Template__c` also gains `Scope__c`. Snapshot
  writer + builder controller filter catalog reads to entries where
  `catalog.Scope__c IN (null, template.Scope__c)`.
- UX for scope management: deferred. Admins set values via record
  edit pages until a real management surface is needed.

Future enhancement path: convert `Scope__c` from Text to a Lookup
on a `Catalog_Scope__c` custom object if customers hit the limits of
free-form string scoping. The migration is a one-way schema change
that can ship in a later wave.

### Interaction with the override math

Today's "shared catalog → read-only inherited mode" decision counts
bindings globally. With scoping, the more correct rule is:

> A catalog entry is "shared" from this template's perspective when
> it has >1 binding **in scope** (matching the template's `Scope__c`
> or unscoped).

For v1 we ship the simpler global-count rule; scoping is mostly
disjoint in practice, so the edge case is rare. Revisit if real
customers hit it.

## UX wireframes

### Catalog browser

A new surface in the builder. Without real search/filter/group, a 50K-row
catalog is unusable. Tag-as-LongTextArea (see Open questions) only works
if there's an actual tag picker affordance.

```
┌─ Question Catalog ─────────────────────────────────────────────┐
│                                                                │
│  🔍 [Search question text or tags...]                          │
│                                                                │
│  Filters:  [ Type ▾ ]  [ Tag ▾ ]  [ Used by N+ templates ▾ ]   │
│            [ × clear ]                                         │
│                                                                │
│  Showing 1,272 entries · sorted by Most Used ▾                 │
│  ──────────────────────────────────────────────────────────    │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Enter the date of service for the most recent report.    │  │
│  │ 📅 Date · used in 60 templates · steritech_700, pco      │  │
│  │ [ Use in template ]  [ Edit catalog entry ]              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ What did you observe?                                    │  │
│  │ ⦿ Multiple Choice · 2 options · used in 56 templates     │  │
│  │ tags: steritech, observation                             │  │
│  │ [ Use in template ]  [ Edit catalog entry ]              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Briefly describe the chemical/item.                      │  │
│  │ 📝 Text Area · used in 24 templates · chemicals, safety  │  │
│  │ [ Use in template ]  [ Edit catalog entry ]              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                │
│  ⌃ Bulk actions:  [ Merge selected ]  [ Add tag ]              │
└────────────────────────────────────────────────────────────────┘
```

Key affordances:
- Default sort by **Most Used** — admins find the highest-leverage
  entries first
- **Usage count** ("used in 60 templates") signals catalog vs. one-off
  questions at a glance
- **Bulk merge** is a power-user affordance (the Phase 2.1 follow-up
  surfaces here)
- **Edit catalog entry** is the cross-template change path; it should
  open a modal that prefixes the form with "This change affects N
  templates" (next wireframe)

### "Edit catalog entry" confirmation

The dangerous path. Without explicit warning, admins will edit the
catalog thinking they're editing one template.

```
┌─ Edit Catalog Entry ───────────────────────────────────────────┐
│                                                                │
│  ⚠ This catalog entry is used in 60 templates.                 │
│  Changes will apply to all of them on next snapshot rebuild.   │
│                                                                │
│  Question text:                                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Enter the date of service for the most recent report.    │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                │
│  Type:  [ Date ▾ ]                                             │
│  Required:  ●Yes  ○No                                          │
│  Tags:  [ steritech_700 × ] [ pco × ] [ + add ]                │
│                                                                │
│  ▼ Affected templates (60)                                     │
│    • Steritech Operational Excellence Audit (2026 Q2)          │
│    • Steritech Audit (2026 Q1)                                 │
│    • Internal pest audit template                              │
│    [ Show all 60 ]                                             │
│                                                                │
│  [ Cancel ]  [ Save & rebuild affected templates ]             │
└────────────────────────────────────────────────────────────────┘
```

### Override badge on builder fields

When editing a question inside a specific template, the admin needs
to know at a glance whether a field is inherited from the catalog or
overridden in this template. Without this, the "three sources of
truth" problem (catalog, override, displayed) confuses users.

```
Question text:
┌────────────────────────────────────────────────────────────────┐
│ Enter the date of service for the most recent report.          │
└────────────────────────────────────────────────────────────────┘
  📎 Inherited from catalog · [ Override in this template ]

  ─── after clicking "Override in this template" ───

Question text (overridden):
┌────────────────────────────────────────────────────────────────┐
│ Enter the date of the last fumigation report.                  │
└────────────────────────────────────────────────────────────────┘
  ✎ Overridden in this template · [ Revert to catalog default ]
  Catalog default: "Enter the date of service for the most..."
```

Same pattern for the Required toggle (the only other overridable field
in v1):

```
Required:  [●] Yes  [○] No   📎 Inherited from catalog (Yes)
                              [ Override in this template ]
```

Color coding (supplemental to the icon, not the only signal):
- 📎 paperclip + neutral text = inherited (no template-specific change)
- ✎ pencil + accent color = overridden (template-specific)

## Governor & perf notes

- Backfill batch: ~1 SOQL + ~2 DML per question. For a 10K-question
  org: ~20K DML rows across batches of 200. Comfortable.
- Snapshot rebuild after migration: one extra SOQL (catalog lookup
  by binding refs) per template rebuild. Likely batched into a single
  query for the template's bindings. Marginal cost.
- Catalog table growth: 1:1 with questions initially. Real dedupe is a
  later workflow. A customer with 50K questions across 200 templates
  ends up with 50K catalog rows — the standard Apex SOQL row limits
  (50K per query) start to matter at scale; org-level analytics
  queries on catalog should add filters.

## Risks

| Risk | Mitigation |
|---|---|
| Migration touches every Form_Question__c in every org | Idempotent, batch-driven, dry-run mode that reports counts before writing. Skip orgs already on v2. |
| Existing customizations reference `Form_Question__c.Question__c` directly | Dual-read shim keeps it working through 2 minor versions. Document the deprecation. |
| Catalog grows unbounded in dedupe-less mode | Type-ahead similarity at create (SOSL) catches near-duplicates at the boundary. Merge workflow handles cleanup. Mass-add staging UI for batched imports. |
| Override fields create N-way merge complexity at read time | Limit overrides to two fields in v1. Force forks for anything else. Revisit only on customer demand. |
| Snapshot writer needs a join — extra query per template | One query batched across all bindings for a template (`WHERE Id IN :catalogIds`). Adds <50ms even for Steritech-scale. |
| Cross-org reuse expectations | Catalog is per-org. Cross-org catalog (a shared question library across customers) is a separate, larger project. |
| Service-provider customers (Steritech) need within-org scoping by downstream customer | `Scope__c` Text(80) field on catalog + template; reads filter to (null OR matching scope). Field shipped early; scope-management UX deferred. |
| Fresh builder-created question stuck in read-only inherited mode | Binding-count-aware editing: when catalog entry has only one binding, edits write through to the catalog directly. Read-only "shared" treatment kicks in once a 2nd binding exists. |

## Decisions

| Decision | Choice | Reason |
|---|---|---|
| Relationship from binding to catalog | Lookup with `restrict` delete | Catalog outlives any single binding; preventing accidental delete protects historical responses |
| Per-binding overrides | Two fields only (`Override_Question__c`, `Override_Required__c`) | Avoid the N-way merge complexity that bigger override sets cause; force forks otherwise |
| Auto-dedupe during migration | No — 1:1 catalog-of-one | Predictable migration. Cross-template dedupe is admin-driven, opt-in, can't make wrong calls automatically |
| Where does `Required__c` live | Catalog default + binding override | Common pattern: "this question is usually required, but in *this* template it's optional" |
| Migration backfill: batch or queueable | Batch (`Database.Batchable`) | Already proven pattern (Phase 1 snapshot backfill). 200-question batches keep heap predictable. |
| Catalog rides briefcase | No | Snapshot has resolved values; catalog is authoring-time data |
| Export shape | Embed catalog content into export | Portability between orgs without requiring catalog sync |
| Builder "+Question" → catalog entry auto-creation | Yes, when `Question_Catalog_Enabled__c` is on | Removes the friction of admins not realizing they need to put questions in the catalog. Closes the workflow gap where builder-created questions skipped the catalog model. |
| Dedup at scale | Layered: type-ahead at create (v1, SOSL), mass-add staging (deferred), merge workflow (deferred) | Hard prevention (unique constraint) blocks legitimate near-duplicates. Soft prevention via type-ahead at the boundary where drift starts. Merge workflow as cleanup safety net. |
| Customer scoping | `Scope__c` Text(80) field; null = global; read paths filter | Cheap insurance against cross-customer pollution (Steritech-class concern). Text avoids committing to a specific scoping object until customer pressure emerges. |
| Search engine for type-ahead | SOSL (native Salesforce search) | Token-matching with stemming, already indexed, free. Vector-search upgrade path open if platform ships native support. |

## Open questions

1. **Do we want a `Form_Question_Catalog_Tag__c` junction object** for
   tagging, or is `Tags__c` LongTextArea good enough? Junction is
   cleaner for filtering at scale; LongTextArea is simpler. Lean: text
   field in v1, junction if/when filtering needs index support.
2. **Should the catalog have its own permission set?** Today, "admin
   creates questions, user reads" works via existing perms. Catalog
   doesn't change that — same model. No new perm set needed.
3. **Versioning of catalog entries?** A catalog entry could itself be
   versioned (entry v1 → v2 over time). Out of scope for v1; templates
   reference the *current* version of a catalog entry. Future Pillar
   8 territory.

## Estimated effort

- Schema + perm sets + briefcase (skip): 0.5d
- Catalog SObject + 30 field migrations: 1d
- Backfill batch + tests: 1d
- Snapshot writer refactor + tests: 1d
- Builder controller `getFormDetails` update: 0.5d
- Builder LWC "pick from catalog" UX: 2d (most of the UI surface)
- Exporter / importer updates: 1d
- Dual-read / dual-write shim: 1d
- Integration + smoke test: 1d
- Buffer: 1d

**~10 dev-days end-to-end**, spread over ~2 weeks given review cycles.
Bigger than Phase 1 (~7 dev-days); the builder UX work is the largest
single chunk.

## Wave timeline

Reflects what's actually shipped vs. what's pending. Each wave is
independently deployable and reversible.

| Wave | Slice | Status |
|---|---|---|
| 35 | Schema (catalog SObject + 30 fields + 3 binding fields + feature flag + perms) | ✅ shipped |
| 35.1 | Catalog backfill batch (catalog-of-one) | ✅ shipped |
| 35.2 | Snapshot writer resolves through catalog | ✅ shipped |
| 35.3 | Builder controller dual-read shim | ✅ shipped |
| 35.4 | Builder catalog provenance badge v1 (read-only) | ✅ shipped |
| 35.5 | "Open catalog entry" navigation button | ✅ shipped |
| 35.6 | Page layout for catalog records | ✅ shipped |
| 35.7 | In-place override / revert flow + correctness fix | ✅ shipped |
| **35.8** | **Auto-create catalog from builder + binding-count-aware editing** | next |
| 35.9 | Type-ahead similarity at create (SOSL) | pending |
| 35.10 | `Scope__c` field + read-side filtering | pending |
| 35.11 | Mass-add staging UI | pending |
| 35.12 | Merge workflow (catalog dedupe) | pending |

35.8 closes the most-noticed workflow gap (builder-created questions
skipping the catalog). 35.9-35.12 are scale-readiness work; ship in
priority order as customer pressure emerges.

## Sequencing within Pillar 2 (original)

1. Schema + catalog SObject deploy (no behavior change)
2. Backfill batch (one-shot; produces catalog-of-one for every org)
3. Snapshot writer refactor (writes resolve via catalog)
4. Dual-read shim in builder controller
5. Builder UI "pick from catalog" affordance
6. Exporter / importer updates
7. Tests, smoke test, deploy

Cut points (ship-and-iterate boundaries): land 1-3, ship, soak. Then
4-7 as a second wave.
