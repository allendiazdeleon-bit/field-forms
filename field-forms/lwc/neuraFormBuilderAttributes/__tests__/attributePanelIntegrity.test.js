import * as fs from 'fs';
import * as path from 'path';

/**
 * Attribute-panel integrity tests.
 *
 * The builder's attribute panel is metadata-driven: Form_Setting_Field__mdt
 * records name the field API names that lightning-input-field binds. Two
 * failure modes have shipped repeatedly and are locked out here:
 *
 *   1. PHANTOM FIELD: a Form_Setting_Field label that doesn't exist on any
 *      builder object renders a broken input (Number's panel bound
 *      Decimal__c, which was never a real field).
 *
 *   2. MISSING FLS: lightning-input-field silently HIDES fields the user
 *      can't read — no error, the input just isn't there. A field deployed
 *      via metadata gets no FLS for anyone, so every panel-bound field must
 *      be granted in FieldForms_Admin or the builder looks broken for every
 *      user (this bit brand scope, the Brand Hub columns, and the Lookup
 *      config fields in the same week).
 *
 * fs-based like typeRegistry.test.js: reads the repo's metadata directly so
 * the contract is enforced at CI time, not discovered in a demo.
 */

// From .../field-forms/lwc/neuraFormBuilderAttributes/__tests__/ up 4 levels
// lands at the repo root.
const REPO_ROOT = path.resolve(__dirname, '../../../..');

const BUILDER_OBJECTS = [
    'Form_Question__c',
    'Form_Template__c',
    'Form_Page__c',
    'Form_Section__c'
];

// Standard fields bindable without a field-meta file or FLS row.
const STANDARD_FIELDS = new Set(['Name']);

function readFile(rel) {
    return fs.readFileSync(path.join(REPO_ROOT, rel), 'utf8');
}

function listDir(rel) {
    const dir = path.join(REPO_ROOT, rel);
    if (!fs.existsSync(dir)) return [];
    return fs.readdirSync(dir);
}

/** Field API names the attribute panel can bind (Form_Setting_Field labels). */
function panelFieldApiNames() {
    return listDir('field-forms/customMetadata')
        .filter((f) => /^Form_Setting_Field\.[^.]+\.md-meta\.xml$/.test(f))
        .map((f) => {
            const m = readFile(`field-forms/customMetadata/${f}`).match(/<label>([^<]+)<\/label>/);
            return m ? m[1].trim() : null;
        })
        .filter(Boolean);
}

/** Map of field API name -> [{ object, flsEligible }] across builder objects. */
function builderFieldIndex() {
    const index = new Map();
    for (const obj of BUILDER_OBJECTS) {
        for (const file of listDir(`field-forms/objects/${obj}/fields`)) {
            const api = file.replace('.field-meta.xml', '');
            const xml = readFile(`field-forms/objects/${obj}/fields/${file}`);
            // Universally-required and master-detail fields have no FLS rows.
            const flsEligible =
                !xml.includes('<required>true</required>') &&
                !xml.includes('<type>MasterDetail</type>');
            if (!index.has(api)) index.set(api, []);
            index.get(api).push({ object: obj, flsEligible });
        }
    }
    return index;
}

describe('attribute panel metadata integrity', () => {
    const panelFields = panelFieldApiNames();
    const fieldIndex = builderFieldIndex();
    const adminPermset = readFile(
        'field-forms/permissionsets/FieldForms_Admin.permissionset-meta.xml'
    );

    test('every panel-bound field exists on at least one builder object', () => {
        const phantoms = panelFields.filter(
            (api) => !STANDARD_FIELDS.has(api) && !fieldIndex.has(api)
        );
        if (phantoms.length) {
            throw new Error(
                `Form_Setting_Field records bind fields that don't exist on any builder object (broken inputs):\n  - ${phantoms.join('\n  - ')}`
            );
        }
    });

    test('every panel-bound field is granted in FieldForms_Admin', () => {
        const missing = [];
        for (const api of panelFields) {
            const owners = fieldIndex.get(api);
            if (!owners) continue; // phantom — reported by the test above
            for (const { object, flsEligible } of owners) {
                if (!flsEligible) continue;
                const key = `<field>${object}.${api}</field>`;
                if (!adminPermset.includes(key)) {
                    missing.push(`${object}.${api}`);
                }
            }
        }
        if (missing.length) {
            throw new Error(
                `Panel-bound fields with no FieldForms_Admin FLS — lightning-input-field will silently hide them for every user:\n  - ${missing.join('\n  - ')}\nAdd <fieldPermissions> entries (editable + readable) to FieldForms_Admin.`
            );
        }
    });
});
