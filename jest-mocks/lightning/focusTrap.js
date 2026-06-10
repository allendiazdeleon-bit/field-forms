// Jest stub for lightning/focusTrap — the sfdx-lwc-jest version in use
// doesn't ship one, and the vendored avonniIconPicker imports it, which
// made every suite that transitively mounts the icon picker fail to LOAD
// (neuraFormBuilderAttributes). A bare container is enough for unit tests.
import { LightningElement } from 'lwc';
export default class FocusTrap extends LightningElement {}
