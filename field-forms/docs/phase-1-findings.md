# Phase 1 Findings — Load Test + Scale Ceilings

**Date:** 2026-05-25
**Org tested:** afcc_apr26@neuraflash.com
**Companion doc:** [snapshot-v2.md](snapshot-v2.md)

After shipping the v2 snapshot (Wave 33), a Steritech-shape load test was
run end-to-end against the deployed schema. It surfaced two real scale
ceilings — one validated as a known design choice, one as a new finding
worth tracking. Both are documented below.

## Test shape

| | |
|---|---|
| Template name | `LOAD_TEST_v2_1779736187434` |
| Sections | 130 |
| Questions | 1,300 (10 per section) |
| Value_Set__c per question | 1,465 chars (18 multiple-choice options) |
| Total snapshot size | ~3.2 MB |
| Steritech (real) for comparison | ~858 KB / 1,272 questions |

The synthetic intentionally produces a payload **4× larger than real
Steritech** because each question carries the full 18-option Value_Set__c.
If v2 handles 3.2 MB, it handles real Steritech comfortably.

Scripts (left under `/tmp/` on the machine that ran them, not in the
repo): `v2_load_build.apex` (creates the template) and
`v2_load_rebuild_async.apex` (enqueues the production
`NeuraFormSnapshotQueueable`).

## Result 1 — Snapshot rebuild scales cleanly under async heap

```
Queueable status:      Completed (errors: 0)
Queueable elapsed:     1,000 ms (queued → completed, wall clock)
Total chunk rows:      30
Total snapshot bytes:  3,242,885 (~3.2 MB)
Legacy fields nulled:  true

Per payload type:
  Pages:              1 chunk,    263 bytes
  Sections:           1 chunk,   47 KB
  Questions:         25 chunks, 3.1 MB,  max chunk 130,292 bytes
  PageConditions:     1 chunk,   "[]"
  SectionConditions:  1 chunk,   "[]"
  QuestionConditions: 1 chunk,   "[]"
```

A re-snapshot triggered by a 1,300-row update of `Form_Question__c.Column__c`
produced the same chunk count and distribution — confirming the
delete-then-insert idempotency at scale.

### Heap finding: sync mode (6MB) cannot rebuild Steritech-scale forms

Two attempts at calling `NeuraFormLogic.processTemplates` synchronously
from Anonymous Apex failed with `LimitException: Apex heap size too
large` (7,507,464 and 6,899,036 bytes — both over the 6MB sync cap).

This is not a v2 regression. The production trigger pipeline runs the
snapshot rebuild through `NeuraFormSnapshotQueueable`, which gets the
12MB async heap. Async completed the same workload in 1 second.

**Implication:** any caller that invokes `processTemplates` from a
synchronous context (an `@AuraEnabled` controller, a Flow action, a
trigger that runs the rebuild inline rather than enqueueing) will fail
on Steritech-scale templates. The existing trigger flow is safe; future
callers need to enqueue.

### Heap optimization opportunity (future)

`NeuraFormSnapshotV2.chunkJsonElements` builds chunks via Apex string
concatenation (`currentString += jsonString`). Apex strings are
immutable, so every `+=` allocates a new string — transient heap use is
roughly 3× the final payload. Async's 12MB absorbed it for our 3.2MB
test, but at 4× this scale (still plausible for a more deeply branched
compliance audit), it could get tight.

Easy fix when needed: accumulate into a `List<String>` and call
`String.join(',')` at the end. Not blocking; flag for Phase 2.

## Result 2 — Builder UI hits a scale cliff around ~1,000+ questions

Opening `LOAD_TEST_v2_*` in the builder froze the tab for ~10 seconds
and used **~2.6 GB of memory**.

### Cause

[neuraFormBuilder](../lwc/neuraFormBuilder/) renders every question, in
every section, in every page, as a real DOM tree with no virtualization:

- 1,300 questions × ~5 LWC instances per question (component shell +
  drop zone + handles + options parser + value-set editor) ≈ **6,000+
  live LWC components**
- Each question's 1.5 KB `Value_Set__c` parses into 18 option components
  → another **~23,000 option DOM nodes**
- 23 `console.log` calls in [neuraFormBuilder.js](../lwc/neuraFormBuilder/neuraFormBuilder.js),
  several of which `JSON.stringify` the entire form data on every state
  change

LWC framework overhead per component instance is ~100-500 KB (Proxy
traps, reactive metadata, shadow DOM). At 6,000+ instances, **2.6 GB is
in the expected range.** The 10-second freeze is the main thread
building all of that synchronously on first render.

### Why v2 surfaced this

Before v2, the legacy snapshot cap (393K) silently dropped chunks past
the third Questions_JSON field. A 1,300-question form couldn't actually
*exist* end-to-end — the builder would have loaded a partial form and
been fast. v2 removed that ceiling, which made this builder ceiling
reachable.

### Implications

| Audience | Impact |
|---|---|
| **Real customers (Steritech-class)** | Negligible. They ingest via the import controller, not the builder. The builder is not the authoring path for compliance audits this size. |
| **Internal admins / power users** | They cannot effectively edit Steritech-scale templates in the builder. They can edit smaller forms, and they can edit normalized records via SOQL/Workbench. |
| **Small / medium forms (<200 questions)** | Builder is fine. Well within the original design envelope. |

## Followups (not blocking Phase 1)

1. **Briefcase deploy.** `Form_Template_Snapshot__c` needs adding to
   `FieldForms_Default.briefcase` for offline mobile to prime v2
   chunks. Blocked on this CLI version's missing `BriefcaseDefinition`
   registry support. Required before v2 ships to offline users. Fix:
   `npm install -g @salesforce/cli@latest` and redeploy.

2. **Builder scale phase.** A separate workstream to make the builder
   usable at Steritech scale:
   - Virtualize the question list
     (`lightning-virtual-list` or IntersectionObserver-based lazy
     mount)
   - Lazy-render non-active pages: only mount the currently-visible
     page; defer others until selected
   - Strip the `console.log` / `JSON.stringify` calls that fire on
     every render
   - Consider a "compact mode" that shows section summaries with
     click-to-expand for questions

   Estimated effort: 1-2 weeks. Schedule when an internal user
   actually needs to edit a large template, or before we onboard a
   customer who wants to author at scale.

3. **Chunker heap optimization.** Move
   `NeuraFormSnapshotV2.chunkJsonElements` from string concatenation
   to `List<String>` + `String.join`. ~2 hours. Schedule before any
   customer pushes past 4× our test (~12+ MB snapshots).

4. **Steritech converter.** Produces a real Steritech import JSON
   from the customer's audit file (`steritech.json`). Validates v2
   against the actual customer payload rather than a synthetic.
   Originally Phase 1 Step 3 in the architecture plan; deferred.

## Cleanup

The test template is left in afcc_apr26 for inspection. To remove it
plus all its sections / questions / snapshot chunks (master-detail
cascades take care of the chain):

```apex
delete [SELECT Id FROM Form_Template__c WHERE Name LIKE 'LOAD_TEST_v2_%'];
```
