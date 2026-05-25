/**
 * Dotted-path resolver for getRecord results — extracted from
 * neuraFormRenderer's resolveFieldPath in wave 32. Used by
 * applySourceDefaults to read host-record fields like
 * "WorkOrder.Account.Name" off the @wire(getRecord) output.
 *
 * Why pure-module instead of method-on-renderer:
 *   uiRecordApi has two distinct nested-shape conventions for spanning
 *   relationships and the unit tests below lock in the behavior for
 *   both. Without isolation, a tweak to the walker (say, supporting a
 *   new shape variant) would have no safety net.
 *
 * Shape contract — uiRecordApi getRecord results look like:
 *
 *   {
 *     apiName: 'WorkOrder',
 *     fields: {
 *       Description: { value: 'Inspect roof' },                  // leaf primitive
 *       Account: {                                               // spanning lookup
 *         value: { fields: { Name: { value: 'Acme' } } }
 *       }
 *     }
 *   }
 *
 *   Both `node.value.fields` and `node.fields` are accepted as the
 *   spanning container — older LDS responses use the former, newer
 *   ones occasionally surface the latter.
 */

/**
 * Walk a getRecord result via a dotted path. The leading object name
 * (e.g. "WorkOrder" in "WorkOrder.Account.Name") is optional — it's
 * dropped when it matches the record's apiName so callers can pass the
 * field path as configured by the admin without normalization.
 *
 * @param {object|null|undefined} record   The getRecord result.
 * @param {string|null|undefined} fullPath The dotted path.
 * @returns {*}  The resolved leaf value, or undefined when any
 *               intermediate is missing.
 */
export function resolveFieldPath(record, fullPath) {
    if (!record || !fullPath) return undefined;

    const parts = String(fullPath).split('.');
    // Drop the leading object name if present (WorkOrder.Account.Name -> Account.Name).
    if (parts.length > 1 && parts[0] === record.apiName) parts.shift();

    let current = record.fields;
    for (let i = 0; i < parts.length; i++) {
        if (!current) return undefined;
        const node = current[parts[i]];
        if (node === undefined) return undefined;
        const isLast = i === parts.length - 1;
        if (isLast) {
            // Leaf: extract .value or the bare primitive.
            return node && typeof node === 'object' && 'value' in node
                ? node.value
                : node;
        }
        // Spanning: follow into the related record's fields. Both shapes
        // surface in real getRecord results depending on the API version
        // and which call-site triggered the wire.
        current = (node && node.value && node.value.fields)
            || (node && node.fields)
            || undefined;
    }
    return undefined;
}
