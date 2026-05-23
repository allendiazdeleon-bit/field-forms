import { LightningElement, api } from 'lwc';

/**
 * Reusable empty-state surface. Use anywhere a list, picker, or surface
 * has nothing to show. Slot in a primary action via the default <slot/>.
 *
 * Pure CSS (no static-resource icons) so it works offline on FSL Mobile.
 */
export default class NeuraEmptyState extends LightningElement {
    /** lightning-icon name, e.g. "utility:open_folder". Optional. */
    @api iconName;
    /** Optional icon variant: 'default', 'success', 'warning', 'error', 'inverse'. */
    @api iconVariant = 'default';
    /** Headline. Required for the empty state to render meaningfully. */
    @api heading;
    /** Supporting body copy. */
    @api body;
}
