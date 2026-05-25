/**
 * Type registry — single source of truth for routing a Form_Question__c
 * Type__c value to the right input component + its render config.
 *
 * Before this module existed, neuraFormAnswer had a ~20-getter chain
 * (`isText`, `isDate`, `isToggle`, ...) and a 25-branch HTML template
 * that duplicated the type-string everywhere. Adding a new input type
 * required touching 4+ files and was easy to get wrong — wave 7's
 * Pass/Fail/N-A bug (MasterLabel mismatch vs picklist API name) was
 * exactly the failure mode this registry prevents: one row, one place,
 * one source of truth.
 *
 * Shape vocabulary
 * ----------------
 * Each entry has a `shape` that maps to a template block in
 * neuraFormAnswer.html. Multiple types share a shape when they only
 * differ by the HTML `type` attribute or a similar small config:
 *
 *   nativeInput  Renders <lightning-input>. Used by Text / Date / Time /
 *                Number / Email / Phone / Toggle / Checkbox / Date Time /
 *                Currency. `subtype` is the `type=` attribute value.
 *                Optional: `formatter`, `step`, `placeholder`.
 *
 *   textArea     Renders <lightning-textarea>.
 *
 *   slider       Renders <lightning-slider>.
 *
 *   checkboxes   Renders a for:each loop of <lightning-input type="checkbox">.
 *
 *   choiceInput  Routes through threshold logic: pills when options <=6,
 *                combobox above. Distinguished further by `mode`
 *                ('multi' | 'single') and `comboboxComponent`
 *                ('multi-select' | 'lightning-combobox').
 *
 *   customSimple Renders a custom LWC that only takes `val` + change.
 *                Used by Pass Fail NA, Geolocation, Scan Barcode, Rating.
 *
 *   customRich   Renders a custom LWC with its own bespoke prop set
 *                (Counter, Repeatable, Lookup, Calculation, File Upload,
 *                Signature, Checklist). Each has its own template branch.
 *
 * Adding a new input type
 * -----------------------
 * 1. Pick a shape from the list above. If your type's prop shape is
 *    different enough to deserve its own template, add a new shape
 *    name + matching template branch in neuraFormAnswer.html.
 * 2. Add a row here with `picklist` (the Type__c API name).
 * 3. Add the matching Form_Setting__mdt record + global value set entry
 *    (the integration playbook in design-system.md has the recipe).
 * 4. Add a row to the smoke test in __tests__/neuraFormAnswer.test.js.
 *
 * Integrity contract
 * ------------------
 * The `picklist` value MUST exactly match:
 *   (a) a <fullName>...</fullName> in
 *       globalValueSets/Form_Question_Answer_types.globalValueSet-meta.xml
 *   (b) the <label>...</label> in
 *       customMetadata/Form_Setting.<...>.md-meta.xml
 * (b) is the MasterLabel that the builder reads as the dragged type's
 * value. (a)/(b)-mismatch is what bit us in wave 7. A registry-driven
 * integrity test in the suite verifies this on every CI run.
 */

export const TYPE_REGISTRY = Object.freeze({
    // ── nativeInput shape — lightning-input variants ──────────────────
    'Text':      { picklist: 'Text',      shape: 'nativeInput', subtype: 'text',     dataId: 'textBox' },
    'Date':      { picklist: 'Date',      shape: 'nativeInput', subtype: 'date',     dataId: 'datePicker' },
    'Time':      { picklist: 'Time',      shape: 'nativeInput', subtype: 'time',     dataId: 'timePicker' },
    'Number':    { picklist: 'Number',    shape: 'nativeInput', subtype: 'number',   dataId: 'numberInput' },
    'Email':     { picklist: 'Email',     shape: 'nativeInput', subtype: 'email',    dataId: 'emailInput' },
    'Phone':     { picklist: 'Phone',     shape: 'nativeInput', subtype: 'tel',      dataId: 'phoneInput' },
    'Toggle':    { picklist: 'Toggle',    shape: 'nativeInput', subtype: 'toggle',   dataId: 'toggle' },
    'Checkbox':  { picklist: 'Checkbox',  shape: 'nativeInput', subtype: 'checkbox-button', dataId: 'checkboxButton' },
    'Date Time': { picklist: 'Date Time', shape: 'nativeInput', subtype: 'datetime', dataId: 'dateTimeInput' },
    'Currency':  { picklist: 'Currency',  shape: 'nativeInput', subtype: 'number',   dataId: 'currencyInput',
                   formatter: 'currency', step: '0.01', placeholder: '$0.00' },

    // ── textArea / slider / checkboxes — singleton shapes ─────────────
    'Text Area':  { picklist: 'Text Area',  shape: 'textArea',   dataId: 'textArea' },
    'Slider':     { picklist: 'Slider',     shape: 'slider',     dataId: 'slider' },
    'Checkboxes': { picklist: 'Checkboxes', shape: 'checkboxes' },

    // ── choiceInput — pills <=6 options, fallback combobox above ──────
    'Multiple Choice': {
        picklist: 'Multiple Choice', shape: 'choiceInput', mode: 'multi',
        comboboxComponent: 'multi-select', dataId: 'multipleChoice'
    },
    'Dropdown': {
        picklist: 'Dropdown', shape: 'choiceInput', mode: 'single',
        comboboxComponent: 'lightning-combobox', dataId: 'dropDown'
    },
    'Radio Buttons': {
        picklist: 'Radio Buttons', shape: 'choiceInput', mode: 'single',
        // Radio Buttons always uses pills — no threshold fallback.
        alwaysPills: true, dataId: 'radioButtons'
    },

    // ── customSimple — `val` + change only ────────────────────────────
    'Pass Fail NA': { picklist: 'Pass Fail NA', shape: 'passFailNa', dataId: 'passFailNa' },
    'Geolocation':  { picklist: 'Geolocation',  shape: 'geolocation', dataId: 'geolocation' },
    'Scan Barcode': { picklist: 'Scan Barcode', shape: 'scanBarcode' },
    'Rating':       { picklist: 'Rating',       shape: 'rating' },

    // ── customRich — bespoke prop shapes ──────────────────────────────
    'Counter':     { picklist: 'Counter',     shape: 'counter',     dataId: 'counter' },
    'Repeatable':  { picklist: 'Repeatable',  shape: 'repeatable',  dataId: 'repeatable' },
    'Lookup':      { picklist: 'Lookup',      shape: 'lookup',      dataId: 'lookup' },
    'Calculation': { picklist: 'Calculation', shape: 'calculation', dataId: 'calculation' },
    'Checklist':   { picklist: 'Checklist',   shape: 'checklist',   dataId: 'checklist' },
    'File Upload': { picklist: 'File Upload', shape: 'fileUpload' },
    'Signature':   { picklist: 'Signature',   shape: 'signature' }

    // Display Text is rendered by neuraFormQuestion, not neuraFormAnswer
    // — intentionally not in this registry.
});

/**
 * Resolve a Type__c value to its registry entry. Unknown types return
 * an empty object so callers using optional chaining don't blow up.
 */
export function lookupTypeConfig(inputType) {
    return TYPE_REGISTRY[inputType] || {};
}
