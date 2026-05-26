# Phase 2 — Pillar 5: Scoring + Findings

**Status:** Draft for review
**Scope:** Phase 2 of the Enterprise Readiness initiative
**Decides:** How form responses produce weighted scores and tracked exceptions
**Companion docs:** Pillar 2 (Question Catalog), Pillar 3 (Adapter framework), [snapshot-v2.md](snapshot-v2.md)
**Depends on:** Pillar 2 (scoring fields live on Form_Question_Catalog__c)

## Why

Today we capture answers. Customers like Steritech run audits to
produce **outcomes** — a weighted score, a list of exceptions, an
exit-meeting summary, a follow-up work order. The platform produces
the raw data; the customer's downstream system has to compute the
outcome.

That gap is why we're a "form library on Salesforce" instead of an
"inspection management platform." It's also the single biggest revenue
moment in the Phase 2 backlog: customers will pay materially more for
the scored-audit product than the form-runtime product.

This pillar closes the gap. It's larger than Pillars 2 and 3 because
it spans schema, runtime calculation, builder UI, renderer UI, and a
new findings workflow.

## What "scoring" means here

Pick an opinionated model for v1, document it, defer customization
until customer #3 asks. The opinionated model is the Steritech-style
audit:

- Each question carries a **weight** (point value)
- Each question has **pass criteria** (what answer counts as "pass")
- Section score = sum of weights of passed questions
- Template score = sum of section scores
- Template **pass threshold** decides overall pass/fail

Other models (averages, custom formulas, weighted-categorical) are
deferred. The schema leaves room for them; the runtime ships only
sum-of-weights.

## Design

### New + modified schema

#### Form_Question_Catalog__c (Pillar 2's new object) gains:

```
Weight__c                  Number(5,2)       Point value when passed (default 1, 0 = informational)
Pass_Criteria__c           LongTextArea      JSON: same syntax as Conditions__c
Failure_Photo_Required__c  Checkbox          If failed, technician must attach a photo
Failure_Severity__c        Picklist          Low / Medium / High / Critical
Failure_Auto_Finding__c    Checkbox          Auto-create Form_Finding__c on failure (default true)
```

The Pass_Criteria__c shape mirrors `Conditions__c` so the conditional
engine ([conditionalRenderingEvaluator.js](../lwc/neuraFormRenderer/conditionalRenderingEvaluator.js))
can be reused. Example:

```json
{
  "all": [
    { "resource": "self", "operator": "equals", "value": "Yes" }
  ]
}
```

`"self"` is a new resource keyword meaning "this question's own
answer." Otherwise existing syntax (`resource` = another question's
external_ref) just works.

#### Form_Section__c gains:

```
Max_Score__c               Number(7,2)        Formula: SUM of catalog Weight__c for active questions
                                              (or denormalized for perf; see Decisions)
```

No runtime score field on the section — runtime score lives on the
response (see below).

#### Form_Template__c gains:

```
Max_Score__c               Number(8,2)        Formula or denormalized
Pass_Threshold_Percent__c  Percent           e.g. 80% (NULL = no pass/fail concept)
Scoring_Enabled__c         Checkbox          Defaults off; opt-in to scoring per template
```

#### Form_Answer__c gains:

```
Passed__c                  Checkbox          Computed on save; nullable until evaluated
Points_Earned__c           Number(5,2)       Weight if passed, 0 if failed, null if not evaluable
```

#### Linked_Form__c (the response record) gains:

```
Score__c                   Number(8,2)        Sum of Points_Earned across all answers
Max_Score__c               Number(8,2)        Snapshot of template Max_Score at submission time
Score_Percent__c           Percent (formula)  Score / Max_Score
Passed__c                  Checkbox           Score_Percent >= template Pass_Threshold_Percent
Findings_Open_Count__c     Number             Rollup from Form_Finding__c
Findings_Blocking_Count__c Number             Rollup; findings that block submission
```

#### New SObject — `Form_Finding__c`

```
Form_Finding__c  (master-detail to Linked_Form__c)
  Linked_Form__c              Master-Detail
  Form_Answer__c              Lookup (the failing answer that caused this finding)
  Form_Question_Catalog__c    Lookup (resolved at finding-creation time)
  Severity__c                 Picklist (mirrors catalog Failure_Severity__c)
  Photo_Required__c           Checkbox (mirrors catalog Failure_Photo_Required__c)
  Photo_Attached__c           Checkbox (true once a ContentDocumentLink exists)
  Status__c                   Picklist: Open / In Progress / Resolved / Waived
  Due_Date__c                 Date
  Assigned_To__c              Lookup (User)
  Notes__c                    LongTextArea
  External_Reference__c       Text (for integration with external work-order systems)
  Blocks_Submission__c        Formula  (Photo_Required__c AND NOT Photo_Attached__c AND Status__c = 'Open')
```

The renderer prevents form submission while
`Findings_Blocking_Count__c > 0`. The customer's downstream system can
read `Form_Finding__c` directly (or via a Connect API once Phase 3
ships) to generate work orders, dashboards, etc.

### Runtime calculation

On every `Form_Answer__c` insert/update (where the template is
scoring-enabled):

1. Load the question's catalog entry (or use the binding's cached
   resolution).
2. Evaluate `Pass_Criteria__c` against the answer value.
3. Set `Passed__c` and `Points_Earned__c` on the answer.
4. If `Passed__c == false` and `Failure_Auto_Finding__c == true`:
   - Upsert a `Form_Finding__c` (by Linked_Form + Question key)
   - Set severity, photo_required from catalog
   - Set Status__c = Open if newly created
5. If `Passed__c == true`:
   - Resolve any existing Open finding for this answer to Auto-Resolved
6. Recalculate `Linked_Form__c.Score__c` (sum of Points_Earned across
   all answers for this Linked_Form).

All of this happens in a trigger on `Form_Answer__c` (after
insert/update). For bulk submissions, a queueable similar to
`NeuraFormSnapshotQueueable` re-aggregates per-Linked_Form.

### Builder UI impact

New tab on the question editor: **"Scoring"**

- Weight (number input, default 1)
- Pass criteria (uses the existing criteria builder — already has UI
  for `resource` / `operator` / `value`)
- Failure severity (picklist)
- Failure photo required (toggle)
- Auto-create finding on failure (toggle, default on)

Section editor shows live "Max points: 12" computed from contained
questions.

Template-level editor adds **"Scoring"** panel:

- Enable scoring (checkbox)
- Pass threshold % (number input, only visible when scoring enabled)

When scoring isn't enabled (`Scoring_Enabled__c = false`), all of the
above is hidden in the builder and skipped at runtime. Backwards
compatible.

### Renderer UI impact

#### Per-section header

Live score badge: `12 / 15  (80%)` updates as the tech answers
questions. Color: red below threshold, green at/above.

#### Failed-question affordance

When `Passed__c = false` and `Failure_Photo_Required__c = true`, the
question shows a "photo required" prompt that opens the existing photo
attach UI. Until a photo is attached, the question is visually marked
"blocking."

#### Findings panel

Slides in from the right (or bottom on mobile):

```
3 findings — 1 critical blocks submit

Critical
  • Foreign matter contamination
    Section: Food Safety / Cooking
    [Photo required] [Add photo →]

High
  • Cooler temperature out of range
    Section: Temperature Documentation
    [Add notes →]

Medium
  • Pest verification missing
    Section: Pest Prevention
    [Note: not blocking]
```

#### Submit guard

Submit button disabled with hover-tooltip when
`Findings_Blocking_Count__c > 0`. Lists the blocking findings.

### Reporting / dashboards

Out of scope for v1 (renderer/builder is enough surface for first
release). Customers can build native Salesforce reports against
`Form_Finding__c` and `Linked_Form__c` immediately. A future Pillar 7
might ship pre-built dashboards.

## Backward compatibility

- `Scoring_Enabled__c` defaults to false. Existing templates and
  responses behave identically until an admin opts in.
- Existing `Form_Answer__c` records have null `Passed__c` /
  `Points_Earned__c` — interpret null as "not evaluated."
- Linked_Form rollup fields are formula or null until first save.
- New `Form_Finding__c` SObject is additive; nothing else depends on
  it being populated.

## Migration

Two opt-in steps for a customer enabling scoring on an existing
template:

1. Author the scoring rules: open each question in the builder, set
   weight + pass criteria. (Or bulk-set defaults via SOQL / data
   loader for known patterns.)
2. Flip `Scoring_Enabled__c` on the template. Subsequent responses
   are scored.

Optional backfill: `NeuraFormScoreBackfillBatch` re-evaluates existing
Form_Answer__c records for a template, populates Passed__c /
Points_Earned__c, generates Form_Finding__c for historical failures.
Useful for customers who want pre-rollout trend reporting. Off by
default; admins run when ready.

## Risks

| Risk | Mitigation |
|---|---|
| Trigger-driven score recalc explodes governor limits on bulk save | Queueable for >50 answers in one DML; per-answer eval inline below threshold |
| Pass_Criteria__c parse errors break submission silently | Validate at builder save (round-trip parse); show inline error if invalid |
| Findings churn when techs flip-flop answers during a long form session | Auto-resolve closes finding when answer flips to pass; don't delete (audit trail) |
| Photo-required block prevents submit but tech can't take a photo (camera offline) | "Mark as exception" workflow with required notes; logs the override on the finding |
| Customers want averages, not sums | Documented out-of-scope for v1. Add Scoring_Mode__c picklist in v2 if demand. |
| Findings dashboard isn't bundled in v1 | Native Salesforce reports work immediately; customers build their own. Pillar 7. |
| Backfill rewrites historical data | Off by default; admins opt in. Backfill logs every change. |
| `Failure_Photo_Required__c` semantics conflict with existing `Include_Photo__c` | `Include_Photo__c` = always offer photo; `Failure_Photo_Required__c` = require on fail. Both can coexist. Document in field help text. |

## Decisions

| Decision | Choice | Reason |
|---|---|---|
| Scoring storage | Computed runtime, stored on Form_Answer__c and Linked_Form__c | Predictable read perf for reports; recompute on demand for edits via batch |
| Max_Score__c on section/template | Denormalized field updated on snapshot rebuild | Avoids per-question SOQL on every answer save; consistent with snapshot architecture |
| Default `Failure_Auto_Finding__c` | True | Match the common case; turn off for advisory-only questions |
| Findings on auto-resolve | Status changes to Auto-Resolved, not deleted | Audit trail; "this finding once existed" is useful for trend data |
| Block submission on missing photo | Hard block (no override at v1) | Aligns with compliance customers' expectation. "Mark as exception" added in v1.1 if requested. |
| Scoring model | Sum of weights | Opinionated; covers Steritech and similar audits. Other models deferred. |
| `Pass_Criteria__c` evaluator | Reuse conditionalRenderingEvaluator.js | Same syntax = same builder UI = same security review; future replacement of eval() helps both at once |
| Builder visibility | Scoring tab hidden when `Scoring_Enabled__c = false` | Avoids cluttering UI for customers who don't use it |

## Open questions

1. **`Form_Finding__c` ownership / sharing.** Findings need to be
   visible to the assigned-to user, the tech who created them, and
   the admin. Default Salesforce sharing? Manual sharing rules? Lean:
   default to Linked_Form__c's sharing (controlled-by-parent),
   document for customers to layer manual sharing as needed.
2. **`Pass_Criteria__c` against multi-select answers.** Multiple
   choice with multiple selected values: how does `equals` apply?
   Probably add a `containsAll` / `containsAny` operator pair to the
   evaluator. Already useful for conditional rendering too — could be
   a pre-req improvement landed before this pillar.
3. **Scoring versioning across template revisions.** If template v2
   changes a weight, do historical v1 responses re-score? Answer:
   responses pin to their template version (from Phase 1 Pillar 4 if
   we ship it); v1 responses keep v1 weights. Today (no versioning)
   they'd silently re-score. Document the constraint until
   versioning ships.
4. **Conditional pass criteria.** "Pass only if temperature is in
   range AND date is within 24 hours" — compound criteria. The IR
   above supports it via `all` / `any` shape; UI needs to expose it.
5. **Integration with FSL work orders.** A finding could auto-create
   a follow-up WorkOrder. Out of scope for v1; document the integration
   point (`Form_Finding__c.External_Reference__c`).

## Estimated effort

- Schema additions (catalog + section + template + answer + linked_form): 1.5d
- New SObject `Form_Finding__c` + perm sets + briefcase: 1d
- Runtime trigger: evaluate pass criteria, update answer, create findings: 2.5d
  - Bulk-safe handler: 0.5d
  - Pass criteria evaluator integration: 1d
  - Finding upsert / auto-resolve: 1d
- Score rollup (linked_form summary): 1d
- Builder UI — Scoring tab on question editor: 2d
- Builder UI — Template scoring panel: 1d
- Renderer UI — section score badge: 1d
- Renderer UI — findings panel + submit guard: 3d
- Backfill batch (optional, opt-in): 1d
- Tests (Apex + Jest): 3d
- Integration / smoke test on a scored template end-to-end: 1.5d
- Buffer: 1.5d

**~20 dev-days end-to-end.** This is the biggest pillar by ~2x; the
renderer findings UI and the bulk-safe runtime evaluator are the two
chunky pieces.

## Sequencing within Pillar 5

1. Schema (catalog scoring fields + section/template/answer rollups +
   findings SObject). No behavior change.
2. Runtime trigger + score rollup + findings auto-create.
3. Builder UI for scoring rules.
4. Renderer UI: section score badge.
5. Renderer UI: findings panel + submit guard.
6. Backfill batch (optional, ship-it-later).

Cut points: ship 1-2 as one wave (data layer working, opt-in via
SOQL); ship 3 as a second wave (admins can author scoring rules);
ship 4-5 as a third wave (techs see the score and findings in the
renderer). Each wave is independently demoable.
