# Form Template Snapshot v2

**Status:** Approved, implementation in progress
**Scope:** Phase 1, Pillar 1 of the Enterprise Readiness initiative
**Owner:** field-forms platform

## Why

Forms are stored normalized (`Form_Page__c` / `Form_Section__c` / `Form_Question__c`) but the renderer reads a denormalized JSON snapshot on `Form_Template__c`. The snapshot fields cap total payload at ~393K (3 chunks × 131K for Questions, plus single 131K fields for everything else). Steritech and other large compliance audits exceed that cap. The chunking loop in `NeuraFormLogic.updateJSON` silently drops chunk #4+; `*_Conditions__c` aren't chunked at all and silently truncate.

## Design

Move the snapshot off the parent record into a child object:

```
Form_Template_Snapshot__c
  Form_Template__c   Master-Detail → Form_Template__c (cascade delete)
  Payload_Type__c    Picklist: Pages | Sections | Questions | PageConditions | SectionConditions | QuestionConditions
  Chunk_Index__c     Number(3,0)
  Payload__c         LongTextArea(131072)
  External_Id__c     Text(255), unique — composite TemplateId|PayloadType|ChunkIndex
  Schema_Version__c  Text(10) — 'v2.0' today
```

One template's snapshot = N rows. Each payload type is independently chunked. Steritech projects to ~10 rows; future 10MB customer to ~80 rows. Same model.

### Why a child object, not more chunk fields

Adding `Questions_JSON_3__c`, `_4__c`, … doesn't survive the next customer. Permanent metadata bloat, fragile counter switch grows linearly, layout pollution. The current 3-field design was already an extension of a 1-field design — the pattern is empirically unstable.

Alternatives considered and rejected:
- **Static Resource per template** — metadata not data, doesn't ride briefcase
- **ContentVersion attachment** — immutable per version, balloons ContentDocuments, heavier mobile sync
- **External storage (S3)** — breaks offline-first; possible Tier-2 option later

## Compatibility & rollout

- **Legacy fields stay** (`Pages_JSON__c`, `Sections_JSON__c`, `Questions_JSON__c[_1_2]`, `*_Conditions__c`). Writers populate v2 exclusively when the feature flag is on. Readers prefer v2 and fall back to legacy if no snapshot rows exist.
- **Feature flag:** `FieldForms_Configuration__c.Snapshot_V2_Enabled__c` (Checkbox). Defaults off. Interacts with existing `Disable_Form_Template_JSON_Trigger__c` (which still suppresses *all* snapshot generation as a kill switch).
- **Migration:** templates re-snapshot on next save when flag is on. Optional `NeuraFormSnapshotBackfillBatch` for forced rebuild.
- **Deprecation:** legacy fields removed in a future major release (2+ minor versions).

## Rollout sequence

1. Schema deploy (new object, new flag, perm-set + briefcase updates). No behavior change.
2. Apex write path — `NeuraFormLogic.updateJSON` writes v2 when flag on.
3. Apex + LWC read path — prefer v2, fall back to legacy.
4. Smoke test against Steritech-sized synthetic payload.
5. Flag enabled per customer org during rollout.
6. Backfill batch.
7. Future release: drop legacy fields.

## Governor & perf notes

- DML per snapshot: ~10 chunk rows + 1 parent ≈ 11 rows. Well within limits.
- Heap: 858K JSON × overhead ≈ 2-3MB. Sync (6MB) tight; async (12MB) comfortable. Snapshot generation already async via `NeuraFormSnapshotQueueable` — stays async.
- Briefcase: add `Form_Template_Snapshot__c` to `FieldForms_Default.briefcase`. Child rows ride along via master-detail.
- Mobile read: GraphQL subquery `Form_Template_Snapshots__r(orderBy: [{Payload_Type__c: ASC}, {Chunk_Index__c: ASC}])`. Existing `combineAndTransformJSON` helper in `neuraFormMobile.js` already concatenates ordered chunks — that's the assembly path.

## Risks

| Risk | Mitigation |
|---|---|
| Briefcase priming time regresses | Synthetic perf test on Steritech-sized payload before enabling |
| Mobile GraphQL doesn't support the orderBy syntax assumed | Verify with Komaci + offline test harness before locking |
| Existing tests assume 3-field shape | Add v2 tests; keep legacy tests until deprecation |
| Customer customization references `Questions_JSON__c` directly | Keep legacy fields populated through 2 releases; release notes |
| `NeuraFormExportController` builds export from legacy fields | Route through the assembled-snapshot helper |
| Orphan chunks on partial failure | Composite `External_Id__c` upsert; master-detail cascade on delete |

## Decisions

| Decision | Choice | Reason |
|---|---|---|
| Storage model | Child object (Master-Detail) | Native, unbounded, primes via briefcase, cascade delete |
| Chunk all payload types or only Questions? | All six, uniform | Simpler code; defends against `*_Conditions__c` overflow that currently silently truncates |
| Embed schema version on each chunk? | Yes (`Schema_Version__c`) | Cheap insurance for future format migrations |
| Feature flag location | `FieldForms_Configuration__c.Snapshot_V2_Enabled__c` | Existing hierarchy custom setting, already in briefcase |
| Compression (gzip+base64)? | Defer | Adds debugging friction; revisit if even larger customer arrives |
