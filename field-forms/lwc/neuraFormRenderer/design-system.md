# Neura Design System (NDS) — v1

The canonical token reference for Field Forms. All visual properties — color,
typography, spacing, elevation, radius, motion, touch targets — flow from the
tokens defined here. Three top-level container components apply these tokens
via `:host` blocks so they cascade through Shadow DOM into every child LWC:

| Top-level container | CSS file applying tokens |
|---|---|
| Form builder (desktop) | `neuraFormBuilder/neuraFormBuilder.css` |
| Form renderer (used by mobile + desktop) | `neuraFormRenderer/neuraFormRenderer.css` |
| FSL Mobile shell | `neuraFormMobile/neuraFormMobile.css` |

When tokens change, update all three. (LWC doesn't support a runtime-shared
stylesheet in offline contexts — static-resource fonts and CSS aren't
available offline per the Mobile and Offline Developer Guide.)

---

## FSL Mobile constraints baked into the system

- **No custom-font static resources.** Typography uses a system font stack
  (`-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, …`) which renders
  natively on every device with zero bytes of network cost.
- **No toast events** (`lightning/platformShowToastEvent` does not display on
  FSL Mobile). Status communication uses in-page badges, the inline message
  component, or `lightning/alert`/`confirm`/`prompt`.
- **No online/offline detection** (platform constraint). Sync state is
  surfaced via `neuraDraftQueueBadge` driven by the local draft-queue count.
- **Touch targets** default to ≥44px, with a `--neura-touch-mobile` size of
  64px for primary list rows (Apple HIG + gloved-hand allowance).
- **Safe-area insets** are exposed as `--neura-safe-{top,right,bottom,left}`
  so sticky footers/headers respect iOS notch and home-indicator areas.

---

## Token reference

### Color — brand

| Token | Value | Use |
|---|---|---|
| `--neura-color-primary` | `#0070d2` | Primary actions, links, brand surface |
| `--neura-color-primary-hover` | `#005fb2` | Primary on hover |
| `--neura-color-primary-active` | `#00396b` | Primary on press |
| `--neura-color-primary-subtle` | `#e6f0fb` | Subtle primary wash (hover bg, secondary button) |
| `--neura-color-primary-contrast` | `#ffffff` | Text/icon on primary background |
| `--neura-color-primary-gradient` | `linear-gradient(135deg, #0070d2 0%, #1589ee 100%)` | Hero surfaces (resume card) |

### Color — semantic

| Token | Value | Use |
|---|---|---|
| `--neura-color-success` | `#194e2b` | Success text on success-bg |
| `--neura-color-success-bg` | `#ddf3e4` | Success wash |
| `--neura-color-success-strong` | `#45c65a` | Completion screen, success buttons |
| `--neura-color-warning` | `#8a6d00` | Warning text |
| `--neura-color-warning-bg` | `#fff5d6` | Warning wash |
| `--neura-color-warning-border` | `#d4a017` | Warning chip border |
| `--neura-color-error` | `#c23934` | Error text on error-bg |
| `--neura-color-error-strong` | `#a8341c` | Error text on plain bg |
| `--neura-color-error-bg` | `#fdecea` | Error wash |
| `--neura-color-info` | `#0070d2` | Info text |
| `--neura-color-info-bg` | `#f5f9ff` | Info wash (summary card) |
| `--neura-color-info-border` | `#c9def7` | Info chip/card border |

### Color — neutral

| Token | Use |
|---|---|
| `--neura-color-text-primary` | Body copy / titles |
| `--neura-color-text-secondary` | Sub-titles |
| `--neura-color-text-muted` | Metadata, labels |
| `--neura-color-text-disabled` | Disabled state |
| `--neura-color-text-inverse` | Text on dark surfaces |
| `--neura-color-surface` | Cards, list rows, modal bodies |
| `--neura-color-surface-subtle` | Very light gray surface |
| `--neura-color-surface-muted` | Pressed/hover row background |
| `--neura-color-background` | App-level background |
| `--neura-color-border` | Default dividers |
| `--neura-color-border-strong` | Inputs, button outlines |
| `--neura-color-border-subtle` | Light dividers between list rows |
| `--neura-color-overlay` | Modal/sheet scrim |

### Typography

System font stack — `var(--neura-font-family)` — set once at the `:host` of
each top-level container.

| Token | Size | Common use |
|---|---|---|
| `--neura-text-xs` | 11px | Eyebrows, micro-meta |
| `--neura-text-sm` | 12px | Labels, secondary meta |
| `--neura-text-base` | 13px | Default body |
| `--neura-text-md` | 14px | Default UI text |
| `--neura-text-lg` | 16px | Subheads |
| `--neura-text-xl` | 18px | Card titles |
| `--neura-text-2xl` | 22px | Page titles |
| `--neura-text-3xl` | 28px | Hero headlines |

Weights: `--neura-font-weight-{regular,medium,semibold,bold}` → 400/500/600/700.
Line-heights: `--neura-line-height-{tight,base,relaxed}` → 1.2/1.4/1.6.

### Spacing — 4px base scale

| Token | Value |
|---|---|
| `--neura-space-2xs` | 2px |
| `--neura-space-xs` | 4px |
| `--neura-space-sm` | 8px |
| `--neura-space-md` | 12px |
| `--neura-space-lg` | 16px |
| `--neura-space-xl` | 24px |
| `--neura-space-2xl` | 32px |
| `--neura-space-3xl` | 48px |

### Radius

| Token | Use |
|---|---|
| `--neura-radius-sm` (4px) | Inputs, small buttons |
| `--neura-radius-md` (8px) | Cards, sections |
| `--neura-radius-lg` (12px) | Hero cards |
| `--neura-radius-pill` (9999px) | Pills, mobile primary buttons |

### Elevation — four-step scale

| Token | When to use |
|---|---|
| `--neura-shadow-subtle` | Baseline card lift |
| `--neura-shadow-base` | Hover lift / standard card |
| `--neura-shadow-raised` | Modal overflow, raised CTA |
| `--neura-shadow-floating` | Bottom sheet, floating overlay |
| `--neura-shadow-primary` | Brand CTAs (matches primary blue glow) |
| `--neura-shadow-primary-pressed` | Brand CTA pressed state |

### Motion

| Token | Value | Use |
|---|---|---|
| `--neura-motion-fast` | 120ms | State changes (hover, focus, press) |
| `--neura-motion-base` | 200ms | Layout transitions |
| `--neura-motion-slow` | 320ms | Sheet/modal enter |
| `--neura-motion-ease` | `cubic-bezier(0.4, 0, 0.2, 1)` | Default easing |
| `--neura-motion-ease-out` | `cubic-bezier(0, 0, 0.2, 1)` | Enter/reveal |

Components must respect `prefers-reduced-motion: reduce` for accessibility.

### Touch / safe area / z-index / focus ring

| Token | Use |
|---|---|
| `--neura-touch-min` (44px) | iOS HIG minimum tap target |
| `--neura-touch-mobile` (64px) | Roomy list rows for gloved-hand use |
| `--neura-safe-{top,right,bottom,left}` | iOS safe-area-inset values |
| `--neura-z-{base,sticky,overlay,modal}` | Stacking scale |
| `--neura-focus-ring-color` | Focus ring (= primary blue) |
| `--neura-focus-ring-width` (2px) | Focus ring stroke |
| `--neura-focus-ring-offset` (2px) | Distance from element edge |

---

## Migration status

Components already on tokens:

- `neuraFormRenderer` — host tokens + autosave/skip-queue badges + page-enter animation + `draftstate` event
- `neuraFormMobile` — host tokens, empty-state wired via `c-neura-empty-state`, loading wired via `c-neura-skeleton`, sync indicator via `c-neura-draft-queue-badge`
- `neuraFormBuilder` — host tokens
- `neuraFormHeader`
- `neuraFormFooter` — safe-area-inset + token-driven colors
- `neuraFormQuestion` — focus-visible + token colors on skip-btn
- `neuraFormComplete` — token-driven CTA + safe-area
- `neuraFormReview` — full token migration
- `neuraFormSelector` — full token migration
- `neuraMobileButton` — full token migration + focus-visible
- `neuraFormSection` — surface + subtle elevation on tokens
- `neuraFormPage` — `.page-active` enter animation defined here (consumed by renderer wrapper)
- `neuraFormProgress` — conic-gradient progress ring uses tokens
- `toastMessage` — in-page toast surface on tokens (FSL-Mobile fallback for `platformShowToastEvent`)
- `neuraPanel` — sidebar primitive on tokens
- `neuraflashSpinner`, `loadingSpinner` — color/font tokens + reduced-motion fallback
- `neuraFormAnswerInputSignatureType`, `neuraFormAnswerInputSignature` — canvas border + label text on tokens
- `neuraFormAnswerInputRatings`, `neuraFormAnswerInputRatingsItem`, `neuraFormAnswerInputStarRating` — touch targets + focus-visible + tokens
- `neuraFormAnswerInputRadioButtons` — segmented control on tokens + reduced-motion fallback
- `neuraFormAnswerInputMultiSelect` — input + dropdown on tokens
- `neuraFormAnswerInputFileUpload` — Nimbus-capture surface on tokens
- `neuraFormBuilderHeader`, `neuraFormBuilderPageItem` — focus-visible + token fallbacks alongside SLDS variables
- `neuraEmptyState` — new pattern component
- `neuraSkeleton` — new pattern component
- `neuraDraftQueueBadge` — new pattern component

Wave 13 — Type-routing registry + safety-net tests:

- **`neuraFormAnswer/typeRegistry.js`** — single source of truth mapping
  each `Form_Question__c.Type__c` value to its render shape + display
  config. Replaces the previous pattern of having the same type-string
  in 4 places (HTML template branch, is<Type> getter, picklist value,
  Form_Setting__mdt record).
- **10 per-type lightning-input branches in `neuraFormAnswer.html`
  collapsed into 1** `useNativeInput` shape block. The active type's
  HTML `type=` attribute, `data-id`, `formatter`, `step`, `placeholder`
  all come from the registry via getters. Adding a new
  lightning-input-flavored type is now a one-row registry change.
- **All `is<Type>` getters** preserved as thin shims forwarding to the
  registry, so callers don't need to migrate.
- **Jest infrastructure brought up in wave 26** — 50 tests now pass:
  29 smoke tests covering every Type's routing, 16 existing formula
  evaluator tests, and 5 new registry-integrity tests that catch
  wave-7-style picklist/MasterLabel mismatches at CI before they hit
  the org.

Updated playbook — adding a new input type
------------------------------------------

1. Add a row to `typeRegistry.js`. Pick a `shape` from the vocabulary
   in that file's header comment.
2. Add a `<customValue>` to
   `globalValueSets/Form_Question_Answer_types.globalValueSet-meta.xml`
   with `<fullName>` matching the registry's `picklist`.
3. Add `customMetadata/Form_Setting.<Name>.md-meta.xml` with `<label>`
   matching the picklist value (NOT a friendly variant — the builder
   stores the MasterLabel as Type__c). Set `Display_Label__c` to the
   admin-friendly version if different.
4. If the new type uses a custom LWC, add a template branch in
   `neuraFormAnswer.html` that fires on the matching `use<Shape>`
   getter. (lightning-input-flavored types need no template change —
   the existing nativeInput block handles them.)
5. Add a row to the parametric test in
   `__tests__/neuraFormAnswer.test.js` so the smoke suite covers your
   type.

The registry-integrity test (`__tests__/typeRegistry.test.js`) will
catch any contract violation in steps 1-3 on the next test run.

---

Wave 12 — Choice-input modernization (Phase 1 of full UX refresh):

- **`neuraFormAnswerInputChoicePills`** — new mobile-first replacement
  for the combobox / dropdown rendering of choice questions. Pill-shaped
  buttons, one tap to pick, all options visible, wraps on narrow screens.
  Mirrors the visual language of Pass/Fail/N-A and Checklist so the
  whole choice-input system reads as one consistent vocabulary.
- **Aggressive rollout** — Multiple Choice, Dropdown, and Radio Buttons
  ALL render as pills by default (existing forms get the new look
  automatically). Threshold is enforced in `neuraFormAnswer`:
  - **≤ 6 options** → pills
  - **\> 6 options** → fall back to the existing combobox (multi-select
    for Multiple Choice, `lightning-combobox` for Dropdown)
  - Radio Buttons always uses pills (wraps naturally for larger lists;
    the legacy segmented control is preserved as a component but no
    longer the default render path)
- **"Other" reveal** — when a question's Value Set includes an option
  labeled "Other" (case-insensitive) and the question is single-select,
  tapping that pill reveals a `lightning-input` text field below. The
  typed text replaces the stored value; if blanked, falls back to the
  literal "Other" so the question still has a value. Multi-select
  treats Other as a regular option for v1.
- **Storage format unchanged** — single-select stores the plain value
  string; multi-select stores comma-separated (matches the existing
  contract used by `c-neura-form-answer-input-multi-select`).
- **Migration impact** — zero schema change, no admin action required;
  existing forms render with pills as soon as the deploy lands.

---

Wave 11 — Checklist sublist:

- **Checklist input** — `neuraFormAnswerInputChecklist`. Admin-defined
  fixed list of items, each scored Pass / Fail / N-A. Composes the
  Pass/Fail/N-A pattern (wave 7) with the array-JSON storage approach
  (wave 10), distinct from Repeatable in that the **rows are admin-defined**
  rather than user-driven.
- **Rows come from `Value_Set__c`** — admins configure the checklist
  items using the same field used for radio/multi-select options. No
  new schema. Empty-state fallback shows "Checklist has no rows. Set
  Value Set on the question." so admins know what to do.
- **Per-row icon-only Pass/Fail/N-A buttons** so a 10-item checklist
  fits on a phone screen without scrolling.
- **Footer progress indicator** — completion ratio (`"3 of 7"`) +
  thin token-driven progress bar matching the resume-hero progress bar
  in the form selector. Helps the tech track how far through they are
  without counting.
- **Answer storage** — JSON array of `{ label, state }` in
  `Form_Answer__c.Answer__c`. Labels not on the current Value_Set__c
  are pruned on re-render (handles admin editing the value set after
  answers were captured).
- **Tap-to-toggle** matches Pass/Fail/N-A behavior — re-tap to clear.

---

Wave 10 — Repeatable group (variable-length lists):

- **Repeatable input** — `neuraFormAnswerInputRepeatable`. Variable-length
  text list with per-row remove + footer Add Row button. Min/max
  bounds reuse the existing `Form_Question__c.Min__c` / `Max__c` fields.
  Picklist value `Repeatable`. Palette icon `utility:rows`.

**Data-model decision (documented for future contributors):**

Repeatable answers are stored as a **JSON-stringified array** in the
existing `Form_Answer__c.Answer__c` long-text field (131,072 char cap —
plenty of headroom). No new fields, no schema changes, no refactor to
the save / load / draft pipeline — the existing data layer just treats
the value as a string.

Tradeoffs considered:

| Option | Pros | Cons | Chosen? |
|---|---|---|---|
| **A. JSON in existing field** | Zero schema change; offline pipeline already drafts-enabled; v2-friendly upgrade path | Can't query/report on individual rows in SOQL | ✓ v1 |
| B. N child rows per question (Iteration_Index__c) | Each row queryable; clean relational shape | Requires schema change + invasive rewrite of `saveAnswers` / `deleteAnswers` to handle "N answers per question" | future |
| C. New child object `Form_Answer_Row__c` | Most relational | Heaviest schema work; new permissions; new triggers | future |

Migration path A → B/C is straightforward when needed: parse the JSON,
spawn child records, leave the JSON in place for legacy answers.

The component itself parses gracefully — if a question is switched from
a single-text type to Repeatable and existing answers contain plain
text (not JSON), they're surfaced as a single-row pre-population rather
than dropped.

---

Wave 9 — Lookup input (multi-asset inspections):

- **Lookup to Salesforce record** — `neuraFormAnswerInputLookup`. Picks
  a record from the host's related list (the canonical multi-asset case:
  one WorkOrder, N WorkOrderLineItems). Combobox UX with three polite
  fallback states (loading, no related records, missing configuration).
- **Three new Form_Question__c fields** added to support per-question
  configuration:
  - `Lookup_Related_List__c` — relationship API name (e.g. `WorkOrderLineItems`)
  - `Lookup_Child_Object__c` — child object API name (e.g. `WorkOrderLineItem`)
  - `Lookup_Display_Field__c` — field to render in the picker (e.g. `LineItemNumber`)
- **Offline behavior** — uses `lightning/uiRelatedListApi.getRelatedListRecords`
  which IS drafts-aware. Per the FSL Mobile LWC skill, records created
  or deleted while offline won't appear in the picker until the queue
  syncs — document this for admins as a known limit, but for the
  multi-asset case (assets are typically primed via briefcase rules) it
  works as expected.
- **Komaci-friendly wire config** — the qualified `fields` list is
  materialized via a `@track` field updated from `connectedCallback`
  and `renderedCallback` rather than via a getter, so the LWC graph
  analyzer can statically trace the data flow (no false positives
  during `npm run lint:offline`).

---

Wave 8 — Tier 1 input types continued:

- **Counter** — `neuraFormAnswerInputCounter`. Minus/value/plus control sized for gloved-hand use. Min/max/step plumbed via existing `Form_Question__c.Min__c` / `Max__c` / `Slider_Step__c` fields (reused; no new schema needed). Manual number input still exposed for "set to 47" cases. Picklist value `Counter`, palette icon `utility:add`.
- **Date + Time** — built-in `lightning-input type="datetime"` rendered via a template block in `neuraFormAnswer.html`. Zero custom component. Picklist value `Date Time`, palette icon `utility:date_time`.
- **Currency** — built-in `lightning-input type="number" formatter="currency"` with `step="0.01"`. Zero custom component. Picklist value `Currency`, palette icon `utility:currency`.
  - Note: per the FSL Mobile LWC skill, `lightning-input` is en-US locale only on FSL Mobile, so the currency renders as USD regardless of org locale. If the customer ever ships internationally, revisit.

---

Wave 7 — input-type extensibility:

- **Pass / Fail / N-A input** — new `neuraFormAnswerInputPassFailNa` component, the canonical three-state inspection input. Big tap targets, semantic green/red/neutral, tap-to-toggle to clear. Picklist value `Pass Fail NA`. Picklist label `Pass / Fail / N-A`.
- **Integration playbook** documented below — recipe for adding any future input type.

**Audit corrections from earlier in the project (transparent record):**

- Slider was reported as "declared in picklist but missing" — **false alarm**.
  It's fully implemented via `lightning-slider` directly in
  `neuraFormAnswer.html:86`. No action needed.
- Star Rating was reported as "implemented but never invoked" — **also
  false alarm**. It's the active "Rating" renderer
  (`neuraFormAnswer.html:145`).
- The actual orphan code is `neuraFormAnswerInputRatings` +
  `neuraFormAnswerInputRatingsItem` (NPS-style 0-10 numeric tiles,
  commented out at `neuraFormAnswer.html:144`). Left in place,
  token-styled — available to wire up as a future "Rating Scale" type
  if/when desired. Removing them is one delete; wiring them is one
  picklist value + one router branch.

---

## Integration playbook — adding a new input type

A new question/answer type touches **four** files. Once you do it twice
the recipe takes maybe 30 minutes. Use Pass / Fail / N-A (wave 7) as the
reference implementation.

### 1. Picklist value
File: `field-forms/globalValueSets/Form_Question_Answer_types.globalValueSet-meta.xml`

```xml
<customValue>
    <fullName>My Type</fullName>
    <default>false</default>
    <label>My Type (Display Label)</label>
</customValue>
```

The `fullName` is the string that flows through `Form_Question__c.Type__c`
and gets compared in the router. The `label` is what admins see in any
picklist UI. Picklist values cannot contain `/`, so use spaces in the
`fullName` and put nice characters like `/` only in the label.

### 2. Custom metadata record (drives the builder palette)
File: `field-forms/customMetadata/Form_Setting.<TypeName>.md-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata"
                xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                xmlns:xsd="http://www.w3.org/2001/XMLSchema">
    <label>My Type (Display Label)</label>
    <protected>false</protected>
    <values>
        <field>Display_Label__c</field>
        <value xsi:type="xsd:string">My Type (Display Label)</value>
    </values>
    <values>
        <field>Icon__c</field>
        <value xsi:type="xsd:string">utility:check</value>  <!-- SLDS icon -->
    </values>
    <values>
        <field>Order__c</field>
        <value xsi:nil="true"/>
    </values>
    <values>
        <field>Structure__c</field>
        <value xsi:type="xsd:string">Component</value>
    </values>
</CustomMetadata>
```

Filename uses underscores (file system) but the `label` and
`Display_Label__c` can use any characters.

### 3. New LWC component
Directory: `field-forms/lwc/neuraFormAnswerInput<TypeName>/`

Required public API:
- `@api val` — the current value (string / object / array depending on type)
- Fires `change` CustomEvent with `detail: { value }` whenever the user
  changes it

Required for design-system parity:
- Use only Neura tokens (`var(--neura-color-primary)` etc.)
- `:focus-visible` styling on every interactive element
- `min-height: var(--neura-touch-mobile)` on primary tap targets
- `@media (hover: none)` block to suppress hover affordances on touch
- Respect `prefers-reduced-motion: reduce` if you animate anything

Required for LWC compiler:
- Boolean `@api` properties must default to `false` (LWC1099 — see
  `neuraBottomSheet` for the renaming workaround if you need the
  inverse semantics)

### 4. Router wiring
Files: `field-forms/lwc/neuraFormAnswer/neuraFormAnswer.js` and `.html`

In the JS, add an `is<MyType>` getter:

```js
get isMyType() {
    return this.inputType === 'My Type';
}
```

In the HTML, add a template block (in roughly the same area as similar
inputs):

```html
<template if:true={isMyType}>
    <c-neura-form-answer-input-my-type
        data-id="myType"
        val={value}
        onchange={handleChange}
    ></c-neura-form-answer-input-my-type>
</template>
```

### Optional further wiring

These aren't required to ship a working input — they're tuning for
specific behaviors:

- **Validation** (e.g. "require comment when Fail"): use the existing
  criteria builder. Don't bake business rules into the component.
- **Property panel customisations** (e.g. min/max for a counter):
  `neuraFormBuilderAttributes` is where per-type configuration lives.
  Add a property record + UI block if your type needs config beyond the
  built-in fields.
- **Review-screen rendering**: `neuraFormReview` renders answers
  read-only. Most types use the default text representation; if yours
  needs visual styling (e.g. a green/red pill for Pass/Fail), add a
  branch there.
- **Import/export**: `neuraFormImport` / `neuraFormExport` serialize the
  template. If your type stores anything beyond a primitive value
  (e.g. a complex object), check those serializers handle it.

---

Wave 6 — theme toggle UI:

- **`neuraThemeToggle`** — new pattern component. Three-state pill button
  (Auto / Light / Dark) with localStorage persistence under the key
  `neura.theme`. Compact mode is icon-only at 44px touch target.
  Emits `themechange` events with `detail: { theme }`. Wired into the
  mobile shell utility bar at the top of the screen.
- **Theme propagation through nested Shadow DOMs** — discovered (and
  documented) that the renderer's own `:host` token block overrides
  inherited custom-property values from its mobile-shell parent. Fixed
  by having the mobile shell forward the `data-theme` attribute to the
  renderer's host via `setAttribute`, with a `renderedCallback` replay
  so newly-mounted renderers pick up the persisted theme. The same
  pattern applies if you ever add another top-level container — forward
  data-theme to it from whatever opens it.

---

## Theme toggle usage

```html
<!-- Compact (icon only) — fits in a mobile header utility bar -->
<c-neura-theme-toggle
    compact
    onthemechange={handleThemeChange}
></c-neura-theme-toggle>

<!-- Full (icon + label) — fits in a settings panel or desktop chrome -->
<c-neura-theme-toggle
    onthemechange={handleThemeChange}
></c-neura-theme-toggle>
```

Parent JS (mobile shell sample):

```js
handleThemeChange(event) {
    const theme = event.detail.theme; // 'auto' | 'light' | 'dark'
    if (theme === 'dark' || theme === 'light') {
        this.setAttribute('data-theme', theme);
    } else {
        this.removeAttribute('data-theme');
    }
    // Forward to any other top-level containers in this Shadow tree
    // because their :host tokens shadow inherited values.
    const renderer = this.template.querySelector('c-neura-form-renderer');
    if (renderer) {
        theme === 'auto'
            ? renderer.removeAttribute('data-theme')
            : renderer.setAttribute('data-theme', theme);
    }
}
```

The toggle fires `themechange` once on `connectedCallback` with the
value loaded from localStorage, so first-paint reflects the user's
persisted choice without flicker.

---

Wave 5 — dark mode + production wiring:

- **Dark mode v1** — see "Dark mode" section below. Same token names, dark
  values applied via either `@media (prefers-color-scheme: dark)` (OS
  preference, default-on) or `data-theme="dark"` on the host element
  (manual override). The host can opt out of OS-driven dark with
  `data-theme="light"`. Applied to all three top-level containers so
  every child LWC inherits dark colors automatically.
- **Signature flow wired to bottom-sheet** — `neuraFormAnswerInputSignature`
  now opens its Type/Draw chooser and capture canvas inside
  `c-neura-bottom-sheet`. Replaces the old inline expansion that
  awkwardly grew the form page when active. Internal accessibility win:
  the chooser options are now real `<button>` elements (were divs with
  `onclick`) with full focus-visible support. Note for reviewers:
  `neuraFormAnswerInputSignatureType` dropped its `lightning-card`
  wrapper since the sheet provides equivalent chrome.

---

## Dark mode

The system supports three states per host:

| `data-theme` value | Behavior |
|---|---|
| (absent) | Auto: matches OS via `prefers-color-scheme` |
| `light` | Forces light, ignoring OS |
| `dark`  | Forces dark, ignoring OS |

**Why both auto + manual?** The auto path is the default UX everyone
expects (system theme just works). The manual override exists so the
host record page or a future user setting can pin the theme — e.g. a
service technician who prefers dark UI even on a phone that's in light
mode during the day.

**How to toggle from a parent component:**

```js
// In your container LWC:
@track _theme = 'auto'; // 'auto' | 'light' | 'dark'

get rendererHostAttrs() {
    return this._theme === 'auto' ? {} : { 'data-theme': this._theme };
}
```

```html
<c-neura-form-renderer
    data-theme={themeAttr}
    ...
></c-neura-form-renderer>
```

**Components and shadows** automatically swap because every CSS rule
reads from tokens. Shadows are deliberately heavier in dark mode so
elevation remains perceptible on near-black surfaces.

**Special cases reviewers should sanity-check on a dark device:**

- `neuraFormComplete` checkmark — green stays bright enough on dark bg
- `imageAnnotate` page (already dark) — verify chrome contrast
- Signature canvas inside the bottom-sheet — confirm strokes are visible
  (canvas content is user-drawn, not themed)
- PDF download link — primary blue on dark bg meets WCAG AA contrast

---

Wave 4 — mobile-native interaction patterns:

- `neuraBottomSheet` — new pattern component. FSL-Mobile-native modal:
  scrim + slide-up sheet with drag-to-dismiss handle, scrim-tap dismiss,
  escape-key dismiss, three height presets (`auto`/`half`/`full`),
  safe-area-inset padding, focus management, and reduced-motion fallback.
  See "Bottom-sheet usage" below.
- `neuraFormRenderer` — gained swipe-between-pages gestures
  (`handlePageSwipeStart` / `handlePageSwipeEnd`). Right swipe = previous
  page, left swipe = next page. Carefully avoids stealing gestures from
  signature canvases, scrollable lists, and form inputs (the closest()
  bail-out check covers the standard interactive elements).

---

## Bottom-sheet usage

The `c-neura-bottom-sheet` component is the recommended FSL-Mobile pattern
for capture flows that currently render inline (signature, camera, info
editor, etc.). It replaces full-page swaps that cause keyboard layout
shift and gives the technician a native-feeling sheet they can drag down
to dismiss.

**Minimal example:**

```html
<c-neura-bottom-sheet
    open={signatureOpen}
    heading="Capture signature"
    size="half"
    onclose={handleSignatureClose}>
    <c-neura-form-answer-input-signature
        answer={answer}
        onchange={handleSignatureChange}>
    </c-neura-form-answer-input-signature>
    <div slot="footer">
        <lightning-button label="Cancel" onclick={handleSignatureClose}></lightning-button>
        <lightning-button label="Save" variant="brand" onclick={handleSignatureSave}></lightning-button>
    </div>
</c-neura-bottom-sheet>
```

**Public API:**

| Prop | Default | Use |
|---|---|---|
| `open` | `false` | Controlled boolean — bind to the parent's open state |
| `heading` | — | Optional title in the sheet header |
| `size` | `'auto'` | `'auto'` (content height) / `'half'` (50vh) / `'full'` (95vh) |
| `non-dismissible` | `false` | Set to block scrim-tap / drag / escape dismissal (use sparingly — only when the action MUST be confirmed) |
| `hide-close-button` | `false` | Suppress the X button in the header |
| `hide-handle` | `false` | Suppress the drag handle pill (also disables drag-to-dismiss) |

**Slots:**

- default — body content
- `footer` — sticky CTAs / action row

**Events:**

- `close` — fired with `detail: { reason }` where `reason` is one of
  `'scrim'`, `'close-button'`, `'drag'`, or `'escape'`. Parent decides
  whether to actually close (e.g. confirm unsaved work first).

**FSL-Mobile constraints honored:**

- Pure CSS animations (no static-resource deps)
- Uses `lightning/icon` for the close button (not a custom SVG sprite)
- Safe-area-inset padding for iOS home indicator
- `overscroll-behavior: contain` so rubber-band scroll inside the sheet
  doesn't propagate to the host record page beneath the scrim
- Respects `prefers-reduced-motion: reduce`
- No `lightning/platformShowToastEvent` dependency

**Wiring candidates (not yet migrated):**

These existing flows would benefit from being wrapped in
`c-neura-bottom-sheet`. None have been changed yet because they're
stateful and live in production — wrap them deliberately, one at a time:

- `c-neura-form-answer-input-signature` — currently renders inline. A
  half-height sheet would give the technician a larger drawing area and
  a clear "save / cancel" footer.
- `c-image-selector` — full-screen photo overview. Migrate to a
  full-height sheet.
- `c-image-info-editor` — file-name / description edit. Auto-height
  sheet, soft keyboard handles itself.
- `c-neura-form-answer-input-geolocation` capture confirmation —
  auto-height sheet with the captured coords and "Use this / Retry"
  buttons.

---

Additional components on tokens (wave 3 — long-tail completion):

- `neuraFormDropZone`, `neuraFormDropZoneColumn`, `neuraFormDropZoneActions` — drop-target visual feedback with success-strong outline
- `neuraFormCriteriaBuilder`, `neuraFormCriteriaLine` — layout-only files (no colors to migrate)
- `infoEditorPrompt` — token-driven save/close buttons with focus-visible
- `colorsPicker` — focus ring + selection ring on tokens (swatches stay literal — they're data)
- `neuraFormComponentItem` — desktop palette item, tokens as fallback alongside SLDS variables
- `imageTextEditor` — text-overlay editor on tokens
- `imageInfoEditor` — file/description meta on tokens
- `neuraFormSelectorItem` — legacy tile-style selector item migrated for back-compat
- `imageAnnotate` — full annotation surface on tokens (dark canvas chrome retained)
- `imagePainter` — drawing tool icons on tokens; user-stroke colors stay literal
- `imageSelector` — photo-capture flow surfaces on tokens including safe-area-inset
- `imageCropper` — host wrapper migrated; vendored Cropper.js inline CSS left as opaque dependency
- `tagButtonImage` — minor text-color migration

Components still on legacy values (intentional):

- `neuraFormBuilderAttributes` (uses `lightning-record-edit-form` — desktop-only by design)
- `neuraFormDropZoneSection` (single SLDS variable override; no Neura tokens needed)
- `imageInfoViewer` (single `display: none` rule; no tokens needed)
- `neuraFormAIGenerate`, `neuraPageDictation`, `neuraVoiceCapture` (no `.css` files — pure templates)
- `darkInput` (separate dark-mode prototype — defer until dark mode is in scope)
- Avonni-prefixed primitives under `avonni*` (third-party vendored library, do not touch)
- Vendored Cropper.js styles inside `imageCropper.css` (opaque dependency)

---

## How to add a new component

1. Set CSS values to `var(--neura-token-name)`. Never hardcode hex values
   for colors that already have a token.
2. If you need a token that doesn't exist, propose it in PR review rather
   than inlining a one-off value. The whole point is no one-offs.
3. Add `:focus-visible` styles to every interactive element. Use the
   `--neura-focus-ring-*` tokens.
4. Default touch targets to `min-height: var(--neura-touch-min)` for any
   tappable element on mobile.
5. Respect `prefers-reduced-motion: reduce` for any animation longer than
   ~120ms.

## How to update a token

1. Edit the canonical `:host` block in
   `neuraFormRenderer/neuraFormRenderer.css`.
2. Mirror the change in `neuraFormMobile/neuraFormMobile.css` and
   `neuraFormBuilder/neuraFormBuilder.css`.
3. Update the appropriate section of this doc.
4. Run `npm run lint && npm run lint:offline && npm run test:unit` before
   merging. The Komaci ESLint rules (`@salesforce/lwc-graph-analyzer`) are
   already wired into `.eslintrc.json` and will catch any data-flow
   regressions that would break offline priming.
