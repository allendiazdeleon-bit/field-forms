import { TYPE_REGISTRY, lookupTypeConfig } from '../typeRegistry';
import * as fs from 'fs';
import * as path from 'path';

/**
 * Registry integrity tests.
 *
 * Why this file exists:
 *   Wave 7 shipped Pass / Fail / N-A with a broken contract: the
 *   Form_Setting__mdt MasterLabel (the value the builder stores as
 *   Type__c) did NOT match the picklist API name the router checked.
 *   Result: dragging the pill from the palette silently produced a
 *   question that rendered nothing. Caught in user testing, not before.
 *
 *   This test enforces the contract that prevents the same class of bug:
 *
 *   For every TYPE_REGISTRY entry's `picklist`:
 *     (a) There MUST be a <customValue><fullName>...</fullName>
 *         in globalValueSets/Form_Question_Answer_types.globalValueSet-meta.xml
 *     (b) If a Form_Setting__mdt record exists for the type, its
 *         <label>...</label> MUST equal the picklist value.
 *
 *   The reverse direction is also checked: every picklist value in the
 *   global value set must have a TYPE_REGISTRY entry (catches admins
 *   adding picklist values without a renderer).
 */

// From .../field-forms/lwc/neuraFormAnswer/__tests__/ up 4 levels
// lands at the repo root (/Users/.../field-forms/).
const REPO_ROOT = path.resolve(__dirname, '../../../..');

function readFile(rel) {
    return fs.readFileSync(path.join(REPO_ROOT, rel), 'utf8');
}

function listMatching(rel, predicate) {
    const dir = path.join(REPO_ROOT, rel);
    return fs.readdirSync(dir).filter(predicate).map((f) => path.join(rel, f));
}

function extractPicklistFullNames(gvsXml) {
    // Pull every <fullName> that appears inside a <customValue> block.
    // Cheap regex parse is fine for fixture metadata.
    const matches = gvsXml.matchAll(
        /<customValue>[\s\S]*?<fullName>([^<]+)<\/fullName>[\s\S]*?<\/customValue>/g
    );
    return Array.from(matches, (m) => m[1].trim());
}

function extractLabel(mdXml) {
    // Form_Setting__mdt records have a top-level <label>...</label>.
    const m = mdXml.match(/<label>([^<]+)<\/label>/);
    return m ? m[1].trim() : null;
}

/** Form_Setting__mdt records are tagged with Structure__c either
 *  'Component' (a draggable answer-input type) or 'Layout' (Page,
 *  Section, the form root). Only Components need to match a picklist
 *  value — layout items aren't stored on Form_Question.Type__c. */
function extractStructure(mdXml) {
    const m = mdXml.match(
        /<field>Structure__c<\/field>\s*<value[^>]*>([^<]+)<\/value>/
    );
    return m ? m[1].trim() : null;
}

describe('TYPE_REGISTRY integrity', () => {
    const gvsXml = readFile(
        'field-forms/globalValueSets/Form_Question_Answer_types.globalValueSet-meta.xml'
    );
    const picklistValues = new Set(extractPicklistFullNames(gvsXml));

    test('every registry entry has a matching picklist value', () => {
        const missing = [];
        for (const [key, cfg] of Object.entries(TYPE_REGISTRY)) {
            if (!picklistValues.has(cfg.picklist)) {
                missing.push(`${key} (picklist="${cfg.picklist}")`);
            }
        }
        if (missing.length) {
            throw new Error(
                `Registry entries with no matching picklist value in Form_Question_Answer_types:\n  - ${missing.join('\n  - ')}\nAdd a <customValue> with the matching <fullName> to the global value set.`
            );
        }
    });

    test('every Form_Setting__mdt label matches the picklist value for its type', () => {
        // Find Form_Setting metadata records — convention: filename starts
        // with "Form_Setting." and ends with .md-meta.xml. We skip
        // Form_Setting_Field.* and Form_Setting_to_Field.* which are
        // unrelated metadata-driven config records.
        const files = listMatching('field-forms/customMetadata', (f) =>
            /^Form_Setting\.[^.]+\.md-meta\.xml$/.test(f)
        );
        const mismatches = [];
        for (const file of files) {
            const xml = readFile(file);
            const structure = extractStructure(xml);
            // Layout items (Page / Section / Form root) don't render via
            // Form_Question__c.Type__c and aren't in the picklist by design.
            if (structure !== 'Component') continue;
            const label = extractLabel(xml);
            if (!label) continue;
            // The label must appear as a picklist fullName, otherwise the
            // builder will store an unparseable Type__c value.
            if (!picklistValues.has(label)) {
                mismatches.push(
                    `${file}: <label>${label}</label> doesn't match any picklist value`
                );
            }
        }
        if (mismatches.length) {
            throw new Error(
                `Form_Setting__mdt records with labels that don't map to a picklist value:\n  - ${mismatches.join('\n  - ')}`
            );
        }
    });

    test('lookupTypeConfig returns the right entry for known types', () => {
        expect(lookupTypeConfig('Text').shape).toBe('nativeInput');
        expect(lookupTypeConfig('Text').subtype).toBe('text');
        expect(lookupTypeConfig('Currency').formatter).toBe('currency');
        expect(lookupTypeConfig('Currency').step).toBe('0.01');
        expect(lookupTypeConfig('Multiple Choice').shape).toBe('choiceInput');
        expect(lookupTypeConfig('Multiple Choice').mode).toBe('multi');
    });

    test('lookupTypeConfig returns an empty object for unknown types', () => {
        // Optional-chain-safe shape: callers may do this.cfg?.shape.
        expect(lookupTypeConfig('NotARealType')).toEqual({});
        expect(lookupTypeConfig(undefined)).toEqual({});
        expect(lookupTypeConfig(null)).toEqual({});
    });

    test('every native-input registry entry declares the fields the template binds', () => {
        // The template binds `dataId` and `subtype` for every nativeInput
        // entry. Currency additionally binds `formatter`, `step`,
        // `placeholder`. This test guards against a future contributor
        // forgetting one of those fields when adding a new entry.
        for (const [key, cfg] of Object.entries(TYPE_REGISTRY)) {
            if (cfg.shape !== 'nativeInput') continue;
            expect(cfg.dataId).toBeTruthy();
            expect(cfg.subtype).toBeTruthy();
        }
    });
});
