import { LightningElement, api, track } from 'lwc';

/**
 * Three-state theme toggle. Cycles through:
 *   auto  → matches OS preference (default)
 *   light → forces light, ignoring OS
 *   dark  → forces dark, ignoring OS
 *
 * Emits a `themechange` CustomEvent with detail { theme } where theme is
 * one of 'auto' | 'light' | 'dark'. The parent is responsible for
 * applying the value as a data-theme attribute on a top-level container
 * (the design-system tokens already react to data-theme="dark" /
 * data-theme="light" via the renderer/mobile/builder host selectors).
 *
 * Persists the user's choice via localStorage under the key
 * 'neura.theme'. localStorage IS available in the FSL Mobile WebView,
 * so the choice survives between sessions on a single device.
 *
 * Public API:
 *   @api storageKey       override the localStorage key (default 'neura.theme')
 *   @api initialTheme     initial value if nothing is in storage (default 'auto')
 *   @api compact          true → icon-only button (32px); false → button + label (default false)
 *
 * Events:
 *   themechange  detail { theme: 'auto' | 'light' | 'dark' }
 *                fires on connectedCallback (with the loaded value)
 *                and again every time the user cycles the toggle
 */
const STORAGE_KEY_DEFAULT = 'neura.theme';
const VALID_THEMES = ['auto', 'light', 'dark'];
const NEXT_THEME = { auto: 'light', light: 'dark', dark: 'auto' };

export default class NeuraThemeToggle extends LightningElement {
    @api storageKey;
    @api initialTheme = 'auto';
    @api compact = false;

    @track _theme = 'auto';

    get _key() { return this.storageKey || STORAGE_KEY_DEFAULT; }

    connectedCallback() {
        const stored = this._readStoredTheme();
        this._theme = stored || this.initialTheme || 'auto';
        // Tell the parent immediately so first-paint matches the persisted choice.
        this._dispatchThemeChange();
    }

    get iconName() {
        if (this._theme === 'dark')  return 'utility:moon';
        if (this._theme === 'light') return 'utility:daylight';
        return 'utility:salesforce1'; // device-shaped icon = "follow device"
    }

    get label() {
        if (this._theme === 'dark')  return 'Dark';
        if (this._theme === 'light') return 'Light';
        return 'Auto';
    }

    get nextLabel() {
        const next = NEXT_THEME[this._theme] || 'auto';
        return `Switch to ${next} theme`;
    }

    get buttonClass() {
        return this.compact ? 'theme-toggle theme-toggle_compact' : 'theme-toggle';
    }

    handleClick() {
        this._theme = NEXT_THEME[this._theme] || 'auto';
        this._writeStoredTheme(this._theme);
        this._dispatchThemeChange();
    }

    _dispatchThemeChange() {
        this.dispatchEvent(new CustomEvent('themechange', {
            detail: { theme: this._theme },
            bubbles: true,
            composed: true
        }));
    }

    _readStoredTheme() {
        try {
            const raw = window.localStorage && window.localStorage.getItem(this._key);
            if (raw && VALID_THEMES.includes(raw)) return raw;
        } catch (e) {
            // Some FSL WebViews block localStorage when third-party storage
            // is restricted. Treat that as a silent reset to default and
            // don't crash the toggle.
        }
        return null;
    }

    _writeStoredTheme(theme) {
        try {
            if (window.localStorage) window.localStorage.setItem(this._key, theme);
        } catch (e) {
            // Same as above — best-effort persist.
        }
    }
}
