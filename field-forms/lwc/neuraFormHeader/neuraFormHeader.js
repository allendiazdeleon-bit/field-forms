import { LightningElement, api } from 'lwc';

export default class NeuraFormHeader extends LightningElement {
    @api indicatorType;
    @api stepList; // array of steps
    @api currentStep; // value from stepList that is active
    @api currentStepPercentage;
    @api currentStepIndex;
    @api totalSteps;

    // Pillar 5 scoring inputs. All optional — when maxScore is null/0
    // the badge stays hidden so non-scored forms render unchanged. The
    // badge primitive handles its own neutral state when threshold is
    // missing (form mid-completion / no Pass_Threshold_Percent set).
    @api formScore;
    @api formMaxScore;
    @api formScoreThreshold;

    get hasScore() {
        const n = Number(this.formMaxScore);
        return Number.isFinite(n) && n > 0;
    }

    // 1-based index for user-facing "Page X of Y" — currentStepIndex is
    // 0-based internally.
    get currentStepIndexDisplay() {
        const idx = Number(this.currentStepIndex);
        if (!Number.isFinite(idx)) return 1;
        return idx + 1;
    }

    get isNextStep() {
        return this.currentStepIndex < this.totalSteps - 1;
    }

    get nextStep() {
        if (this.isNextStep) {
            return this.stepList[this.currentStepIndex + 1];
        }
        return '';
    }

    // Inline style on the progress fill so the bar width animates between
    // page changes without recomputing the keyframe.
    get progressStyle() {
        const total = Number(this.totalSteps) || 1;
        const idx = this.currentStepIndexDisplay;
        const pct = Math.max(0, Math.min(100, Math.round((idx / total) * 100)));
        return `width: ${pct}%`;
    }

    // Retained for backwards-compatibility with any external callers,
    // but no longer used in the new template.
    get showRightText() {
        return this.indicatorType === 'Ring';
    }
}
