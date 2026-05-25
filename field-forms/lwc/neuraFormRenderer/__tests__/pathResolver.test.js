import { resolveFieldPath } from '../pathResolver';

/**
 * Direct tests for the dotted-path walker. The walker has to handle:
 *   - leaf primitives ({ value: 'x' } or bare values)
 *   - spanning lookups in both shapes (.value.fields vs .fields)
 *   - the leading-apiName drop ("WorkOrder.Description" should equal "Description")
 *   - graceful undefined for missing intermediates
 */

const RECORD = {
    apiName: 'WorkOrder',
    fields: {
        Description: { value: 'Inspect roof' },
        BareField: 'raw value, no value-wrapper',
        Account: {
            value: {
                fields: {
                    Name: { value: 'Acme Inc' },
                    BillingCity: { value: 'Boston' }
                }
            }
        },
        // Spanning lookup using the alternate flat-fields shape some LDS
        // responses surface.
        Asset: {
            fields: {
                Name: { value: 'Roof unit 7' }
            }
        }
    }
};

describe('resolveFieldPath', () => {
    it('returns undefined for null/empty inputs', () => {
        expect(resolveFieldPath(null, 'Description')).toBeUndefined();
        expect(resolveFieldPath(RECORD, '')).toBeUndefined();
        expect(resolveFieldPath(RECORD, null)).toBeUndefined();
        expect(resolveFieldPath(undefined, undefined)).toBeUndefined();
    });

    it('resolves a leaf primitive', () => {
        expect(resolveFieldPath(RECORD, 'Description')).toBe('Inspect roof');
    });

    it('drops the leading apiName segment when it matches', () => {
        expect(resolveFieldPath(RECORD, 'WorkOrder.Description')).toBe('Inspect roof');
    });

    it('does not strip a leading segment that does not match apiName', () => {
        // 'SomethingElse' is not the apiName, so it's treated as a real
        // path segment — and there's no field called SomethingElse,
        // so undefined.
        expect(resolveFieldPath(RECORD, 'SomethingElse.Description')).toBeUndefined();
    });

    it('walks through a spanning lookup (value.fields shape)', () => {
        expect(resolveFieldPath(RECORD, 'Account.Name')).toBe('Acme Inc');
        expect(resolveFieldPath(RECORD, 'WorkOrder.Account.BillingCity')).toBe('Boston');
    });

    it('walks through a spanning lookup (flat fields shape)', () => {
        expect(resolveFieldPath(RECORD, 'Asset.Name')).toBe('Roof unit 7');
    });

    it('returns the bare value when a leaf is not value-wrapped', () => {
        expect(resolveFieldPath(RECORD, 'BareField')).toBe('raw value, no value-wrapper');
    });

    it('returns undefined when an intermediate is missing', () => {
        expect(resolveFieldPath(RECORD, 'Account.MissingField')).toBeUndefined();
        expect(resolveFieldPath(RECORD, 'NoSuchLookup.AnyField')).toBeUndefined();
        expect(resolveFieldPath(RECORD, 'Account.Name.ExtraSegment')).toBeUndefined();
    });

    it('returns undefined when the record has no fields property', () => {
        expect(resolveFieldPath({ apiName: 'X' }, 'X.Name')).toBeUndefined();
    });
});
