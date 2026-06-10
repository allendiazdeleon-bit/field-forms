# Phase 2 — End-to-End Smoke Tests (by persona)

Covers everything shipped in Waves 38–47: Pillar 5 (Scoring + Findings)
and the Steritech import adapter. Run top-to-bottom; each persona's
section assumes the setup in §0 is done and the prior persona's data
exists.

> **Status:** This plan has **not** been executed or auto-verified.
> The code compiles in the editor but was not deployed or run through
> `sfdx-lwc-jest` / Apex tests in this environment (no Node/CLI on the
> author's PATH). Treat every "Expected" as a hypothesis to confirm.

Mark each row **PASS / FAIL / BLOCKED** and add notes. Known gaps are
called out inline with ⚠️ so you don't log them as new bugs.

---

## 0. Setup & prerequisites

| # | Step | Expected | Result |
|---|------|----------|--------|
| 0.1 | Deploy the branch to a scratch/sandbox org: `sf project deploy start -d field-forms` | Deploy succeeds; no metadata errors. ⚠️ The `BriefcaseDefinition` may not deploy on older CLI (known Wave 33 follow-up) — deploy everything else if it errors on that one file. | |
| 0.2 | Run Apex tests: `sf apex run test -l RunLocalTests -w 30` | All Pillar 5 + adapter tests green (NeuraFormScoringEvaluatorTest, FormAnswerScoringTriggerTest, NeuraFormSteritechAdapterTest, etc.). | |
| 0.3 | Run LWC tests: `npm run test:unit` | Green, including the 4 new primitives + `findingsHelpers`. | |
| 0.4 | Assign perm set: `sf org assign permset -n FieldForms_Admin` to your admin user; `FieldForms_User` to a test technician user. | Both assigned without field-level errors. | |
| 0.5 | Open the **Field Forms** app (App Launcher → Field Forms). | App opens with tabs: Form Templates, Linked Forms, Form Findings, Form Export/Import. | |

---

## 1. Persona: Admin / Form Builder

Goal: configure a scored template from scratch and confirm every
scoring control is reachable and saves.

### 1A. Enable scoring at the template level

| # | Step | Expected | Result |
|---|------|----------|--------|
| 1A.1 | Form Templates tab → open (or create) a template → it opens in the builder. | Builder canvas + attributes panel render. | |
| 1A.2 | Select the form/template node (click empty canvas header / template-level selector). | Attributes panel shows template fields. | |
| 1A.3 | Confirm these inputs are present: **Scoring Enabled**, **Pass Threshold Percent**, **Max Score**, **Allow Exception Override**. | All four render (Wave 44 CMDT). | |
| 1A.4 | Set Scoring Enabled = ✓, Pass Threshold Percent = `80`, Allow Exception Override = `Allow`. Save. | Saves without error. Reload the template record — values persisted. | |
| 1A.5 | Leave Max Score blank for now. | Accepts blank (it's rollup-written). | |

### 1B. Configure question-level scoring (catalog)

| # | Step | Expected | Result |
|---|------|----------|--------|
| 1B.1 | Select a question that is linked to a catalog entry (provenance badge shows "linked"/"inherited"). | Question editor opens. | |
| 1B.2 | Scroll to the **Scoring** panel at the bottom of the question editor. | Panel renders with header "Scoring" + the blast-radius hint. | |
| 1B.3 | Set **Weight** = `5`, **Failure Severity** = `Critical`, **Auto-create finding** = ✓, **Require photo** = ✓, **Allow Exception Override** = `Require photo`. | All inputs editable. | |
| 1B.4 | In **Pass Criteria**, paste: `{"all":[{"resource":"self","operator":"equals","value":"Yes"}]}` | Accepts the JSON (textarea in v1). | |
| 1B.5 | Click **Save scoring**. | Success toast / no error. Reopen the catalog record (Form Question Catalog) — fields persisted. | |
| 1B.6 | Select a question with **no** catalog entry. Open the Scoring panel. | ⚠️ Shows the "not linked to a catalog entry" directive instead of the form — expected, not a bug. | |
| 1B.7 | Repeat 1B.1–1B.5 for a second question: Weight `3`, Severity `Medium`, Require photo = ✗, Allow Exception Override = `Inherit`. | Saves. | |
| 1B.8 | Leave a third question with Weight `0` (informational). | Accepts 0. | |

### 1C. Verify Max Score rolls up

| # | Step | Expected | Result |
|---|------|----------|--------|
| 1C.1 | Open a Linked Form for this template (or create one), save any answer to trigger the scoring engine. | Scoring trigger/queueable fires. | |
| 1C.2 | Open the template's `Max_Score__c` (record detail). | ⚠️ Populates **after** the first answer save on a child Linked Form, not on template save. If still blank, confirm an answer was saved. | |

**Section 1 sign-off:** ___ PASS / ___ FAIL — notes:

---

## 2. Persona: Field Technician (mobile / FSL renderer)

Goal: fill out the scored template and exercise the live badge,
findings panel, exception modal, and submit guard. Best run in FSL
Mobile or the `neuraFormMobile` component on a WorkOrder /
ServiceAppointment / WorkOrderLineItem record.

### 2A. Live score badge

| # | Step | Expected | Result |
|---|------|----------|--------|
| 2A.1 | Open a Linked Form for the scored template on a host record. | Form renders; header visible. | |
| 2A.2 | Before answering anything, look at the header. | ⚠️ Score badge may be **absent** until Max Score is computed (first answer save). This is the known silent-degradation behavior — not a crash. | |
| 2A.3 | Answer the Weight-5 question with a **passing** value (`Yes`). | Header score badge shows e.g. `5 / 8 (63%)`, red/✗ (below 80%). | |
| 2A.4 | Answer the Weight-3 question with a **passing** value. | Badge updates to `8 / 8 (100%)`, green/✓. | |
| 2A.5 | Change the Weight-5 answer to a **failing** value (`No`). | Badge drops below threshold → red/✗. Color + icon + bar all flip (not just color). | |

### 2B. Findings panel

| # | Step | Expected | Result |
|---|------|----------|--------|
| 2B.1 | With the Weight-5 (Critical, auto-finding, photo-required) question failing, look at the bottom of the screen. | Sticky summary handle: `⚠ 1 findings · 1 blocks`. | |
| 2B.2 | Tap the handle. | Panel expands; finding card shows `CRITICAL · BLOCKS`, the question title, "Add photo" CTA. | |
| 2B.3 | Tap the finding card header. | Form page-jumps to the question and scrolls it into view (not hidden under the sticky header). | |
| 2B.4 | Make the failing question pass again. | ⚠️ Finding status updates on the **next scoring run** (after save); the panel reflects open/blocking counts from the rollup. Confirm the count drops. | |
| 2B.5 | With zero open findings, check the handle. | Shows `✓ No findings · 0`; expand shows the positive empty state. | |

### 2C. Exception override modal

| # | Step | Expected | Result |
|---|------|----------|--------|
| 2C.1 | Re-fail the Critical question so a blocking finding exists. Expand the panel, tap **Mark exception**. | Modal opens. Because the question's policy is `Require photo` (1B.3), the modal shows the reason picker **and** the "I will attach a photo" checkbox. | |
| 2C.2 | Pick reason `Customer waived`, leave photo checkbox unchecked. | **Mark exception** button stays disabled. | |
| 2C.3 | Check the photo checkbox. | Button enables. | |
| 2C.4 | Pick reason `Other` without detail. | Button disables until the detail textarea has text. | |
| 2C.5 | Fill reason `Customer waived` + photo checkbox, tap **Mark exception**. | Modal closes; toast "Exception recorded. Finding cleared."; the finding card updates to show the exception (no longer blocking). Submit guard's blocking count drops. | |
| 2C.6 | Find a question whose Allow Exception Override resolves to `Disallow` (set one in 1B if needed). Tap Mark exception. | ⚠️ Modal shows the locked message (no reason picker, no confirm) — override path closed by policy. | |

### 2D. Photo hand-off

| # | Step | Expected | Result |
|---|------|----------|--------|
| 2D.1 | On a photo-required finding, tap **Add photo**. | Form scrolls to the source question + toast: "Tap the camera icon on the highlighted question…". ⚠️ It does **not** auto-open the camera (deferred follow-up). | |
| 2D.2 | Tap the question's existing camera/file button, attach a photo. | Photo attaches via the normal question photo flow. | |

### 2E. Submit guard

| # | Step | Expected | Result |
|---|------|----------|--------|
| 2E.1 | With ≥1 blocking finding open, tap Finish → reach Review & Submit. | Submit guard shows score + severity breakdown; submit is a **disabled** dashed-red panel: "Resolve N blocking findings first" + "View findings". | |
| 2E.2 | Tap **View findings**. | Bubbles up (findings panel intent). | |
| 2E.3 | Clear/exception all blocking findings. Return to Review. | Submit button **enabled**; shows the note "Form will submit with N open findings. These remain visible to reviewers." (if non-blocking findings remain). | |
| 2E.4 | Tap **Submit**. | Form submits via the normal completion flow (summary preserved). | |
| 2E.5 | Tap **Save draft** at any point. | Always available; saves without submit. | |

**Section 2 sign-off:** ___ PASS / ___ FAIL — notes:

---

## 3. Persona: Manager / Reviewer (desktop)

Goal: audit a completed/in-progress Linked Form and triage findings
at scale.

| # | Step | Expected | Result |
|---|------|----------|--------|
| 3.1 | Linked Forms tab → open the form from §2. | Record page loads. | |
| 3.2 | Find the **Scoring** section. | Read-only: Score, Max Score, Score %, Passed, Findings Open Count, Findings Blocking Count — values match what the tech saw. | |
| 3.3 | Find the **Form Findings** related list. | Lists each finding with Severity, Status, Blocks Submission, Photo Required, Photo Attached, Exception Reason columns. | |
| 3.4 | Open the exception-cleared finding. | Status = `Resolved-Exception`, Exception Reason / Detail populated. | |
| 3.5 | Form Findings tab → switch list views: **All Open**, **Blocking Submit**, **Critical Open**, **Assigned to Me**. | Each view filters correctly (resolved/waived excluded from open views; blocking view only Blocks=✓; critical view only Severity=Critical). | |
| 3.6 | Confirm a resolved/exception finding does **not** appear in All Open / Blocking / Critical. | Filtered out. | |

**Section 3 sign-off:** ___ PASS / ___ FAIL — notes:

---

## 4. Persona: Integration Admin (Steritech import)

Goal: import the Steritech audit JSON via the auto-detecting adapter.

| # | Step | Expected | Result |
|---|------|----------|--------|
| 4.1 | Form Export/Import tab → import panel. | Import UI renders with a file picker. | |
| 4.2 | Upload `steritech.json` (repo root). | File parses client-side; preview shows a template count > 0. | |
| 4.3 | Confirm import. | Pipeline auto-selects the **Steritech Audit Format** adapter (via `canHandle`), creates the template + pages + sections + catalog entries + bindings. No error. | |
| 4.4 | Open the imported template in the builder. | Pages grouped by first-letter buckets; sections per line item; questions present. | |
| 4.5 | Spot-check a few catalog entries created by the import. | Question text + type look right; near-duplicate questions de-duped to one catalog entry (shared across bindings). | |
| 4.6 | Re-import the same file. | ⚠️ Should update rather than duplicate (master-detail re-import guard). Confirm no duplicate template. | |

**Section 4 sign-off:** ___ PASS / ___ FAIL — notes:

---

## 5. Cross-cutting: backward compatibility & regression

The whole point of the `Scoring_Enabled__c` gate is that nothing
changes for non-scored forms. Confirm it.

| # | Step | Expected | Result |
|---|------|----------|--------|
| 5.1 | Open a Linked Form for a template with **Scoring Enabled = false** (or never set). | No score badge, no findings panel, no submit guard. The original Submit button shows on review. Header/footer/pages unchanged. | |
| 5.2 | Fill + submit that non-scored form. | Behaves exactly as before Pillar 5. | |
| 5.3 | Open an existing pre-Pillar-5 Linked Form (created before this branch). | Renders normally; `Passed__c`/`Points_Earned__c` null = "not evaluated", no errors. | |
| 5.4 | Builder: edit a non-scored question's Basic/Validation/Conditions. | Unchanged; the Scoring panel still shows but editing other fields is unaffected. | |
| 5.5 | Offline (FSL Mobile, airplane mode): open a primed scored Linked Form. | Score badge + findings panel work from briefcase-primed data (Form_Finding__c is primed). Exception save queues for sync. | |
| 5.6 | Regression: dictation, "Same as last visit" prefill, skip-and-return, page swipe still work on a scored form. | All unaffected by the new chrome. | |

**Section 5 sign-off:** ___ PASS / ___ FAIL — notes:

---

## 6. Known gaps (do NOT log as bugs)

- **Score badge hidden when Max Score is null/0.** Silent by design.
  If scoring is on but no question weights are set, the findings panel
  and submit guard still appear while the badge does not. (Discussed;
  consistency/diagnostic improvement is a separate decision.)
- **Desktop `neuraForm`** (non-FSL renderer) does not carry the
  Linked Form scoring data, so the badge won't appear there yet —
  mobile is the supported scoring surface.
- **Photo "Add photo"** scrolls + prompts rather than auto-opening the
  camera.
- **Pass Criteria** is a raw JSON textarea in the builder (guided
  criteria builder is a follow-up).
- **BriefcaseDefinition** may not deploy on older CLI versions.

---

## Overall sign-off

| Persona | PASS / FAIL | Reviewer | Date |
|---------|-------------|----------|------|
| 1. Admin / Builder | | | |
| 2. Field Technician | | | |
| 3. Manager / Reviewer | | | |
| 4. Integration Admin | | | |
| 5. Backward-compat / regression | | | |
