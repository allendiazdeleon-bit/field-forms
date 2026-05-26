import { createElement } from 'lwc';
import NeuraFormScoreBadge from 'c/neuraFormScoreBadge';

/**
 * c-neura-form-score-badge is the Pillar 5 score visualization primitive.
 * Tests assert the three render states (passed / failed / neutral) plus
 * edge cases around missing / zero inputs. Queries hit the shadow DOM to
 * match the project's existing LWC test convention.
 */

async function mount(props = {}) {
    const el = createElement('c-neura-form-score-badge', {
        is: NeuraFormScoreBadge
    });
    Object.assign(el, props);
    document.body.appendChild(el);
    await Promise.resolve();
    return el;
}

function rootClass(el) {
    return el.shadowRoot.querySelector('div.score-badge').className;
}

function icon(el) {
    return el.shadowRoot.querySelector('lightning-icon');
}

function fillStyle(el) {
    // Width is set imperatively in renderedCallback (see component for why).
    return el.shadowRoot.querySelector('.score-badge__bar-fill').style.width;
}

function scoreText(el) {
    return el.shadowRoot.querySelector('.score-badge__score').textContent;
}

function percentText(el) {
    return el.shadowRoot.querySelector('.score-badge__percent').textContent;
}

afterEach(() => {
    while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
    }
});

describe('c-neura-form-score-badge', () => {
    it('renders the passed state when score meets threshold', async () => {
        const el = await mount({ score: 90, maxScore: 100, threshold: 80 });
        expect(rootClass(el)).toContain('score-badge--passed');
        expect(icon(el).iconName).toBe('utility:check');
        expect(icon(el).variant).toBe('success');
        expect(fillStyle(el)).toBe('90%');
        expect(scoreText(el)).toBe('90 / 100');
        expect(percentText(el)).toBe('(90%)');
    });

    it('renders the failed state when score is below threshold', async () => {
        const el = await mount({ score: 60, maxScore: 100, threshold: 80 });
        expect(rootClass(el)).toContain('score-badge--failed');
        expect(icon(el).iconName).toBe('utility:close');
        expect(icon(el).variant).toBe('error');
        expect(fillStyle(el)).toBe('60%');
    });

    it('renders the neutral state when threshold is missing', async () => {
        const el = await mount({ score: 50, maxScore: 100 });
        expect(rootClass(el)).toContain('score-badge--neutral');
        expect(icon(el).iconName).toBe('utility:dash');
        expect(icon(el).variant).toBe('inverse');
        // Bar still shows progress, just without a pass/fail color.
        expect(fillStyle(el)).toBe('50%');
    });

    it('renders neutral with an empty bar when maxScore is zero', async () => {
        const el = await mount({ score: 0, maxScore: 0, threshold: 80 });
        expect(rootClass(el)).toContain('score-badge--neutral');
        expect(fillStyle(el)).toBe('0%');
        expect(scoreText(el)).toBe('0 / 0');
    });

    it('treats null score as zero and renders 0 / Y', async () => {
        const el = await mount({ score: null, maxScore: 100, threshold: 80 });
        expect(rootClass(el)).toContain('score-badge--failed');
        expect(scoreText(el)).toBe('0 / 100');
        expect(fillStyle(el)).toBe('0%');
    });

    it('clamps percent at 100 even when score exceeds max', async () => {
        const el = await mount({ score: 150, maxScore: 100, threshold: 80 });
        expect(fillStyle(el)).toBe('100%');
        expect(percentText(el)).toBe('(100%)');
        expect(rootClass(el)).toContain('score-badge--passed');
    });

    it('omits the label when no label prop is set', async () => {
        const el = await mount({ score: 90, maxScore: 100, threshold: 80 });
        expect(el.shadowRoot.querySelector('.score-badge__label')).toBeNull();
    });

    it('renders the label when provided', async () => {
        const el = await mount({
            score: 90,
            maxScore: 100,
            threshold: 80,
            label: 'Pest Prevention'
        });
        const label = el.shadowRoot.querySelector('.score-badge__label');
        expect(label).not.toBeNull();
        expect(label.textContent).toBe('Pest Prevention');
    });

    it('formats fractional weights without trailing .0', async () => {
        const el = await mount({ score: 2.5, maxScore: 5.0, threshold: 50 });
        expect(scoreText(el)).toBe('2.5 / 5');
    });

    it('exposes a screen-reader-friendly state label', async () => {
        const el = await mount({ score: 90, maxScore: 100, threshold: 80 });
        const group = el.shadowRoot.querySelector('div.score-badge');
        expect(group.getAttribute('aria-label')).toBe('Pass');
        expect(icon(el).alternativeText).toBe('Pass');
    });
});
