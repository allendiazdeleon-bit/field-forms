/**
 * Jest mock for lightning/configProvider — used by Avonni and other
 * internal LWC primitives to access locale / connection / iconUrl
 * configuration. Not in the sfdx-lwc-jest default set.
 *
 * Mock surface is intentionally minimal: callers expect SOME exports,
 * and returning sensible defaults is enough to get past module load.
 */
export function getPathPrefix() { return ''; }
export function getToken() { return undefined; }
export function getTokensFromImports() { return {}; }
export function getCoreInformation() { return {}; }
export function getInternalConfig() { return {}; }
export function getCSPNonce() { return ''; }

// Some Avonni components import a getIconLibrary function.
export function getIconLibrary() { return {}; }
