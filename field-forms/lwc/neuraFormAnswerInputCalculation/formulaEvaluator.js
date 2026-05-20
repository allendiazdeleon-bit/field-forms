// Tiny expression evaluator for Calculation question types.
//
// Supports:
//   - Numeric literals, including decimals.
//   - {{questionId}} references to other answers on the same form.
//   - + - * / % (mod) with standard precedence.
//   - Unary minus.
//   - Parentheses.
//   - Functions: SUM, AVG, MIN, MAX, COUNT, ROUND, ABS, IF.
//
// IF is a strict 3-argument form: IF(cond, then, else). cond is truthy when
// non-zero / non-empty. ROUND(x, n) rounds to n decimal places (n defaults
// to 0). Missing references resolve to 0; division by zero returns NaN which
// is then surfaced as an empty result by the consumer.
//
// Why a hand-rolled parser instead of `new Function(...)`? eval-style
// approaches expose the runtime to whatever an admin types as a formula -
// a footgun in a multi-tenant Salesforce package. This walker is safe by
// construction: only the operators and identifiers in the grammar below
// can ever execute.

const TOKEN = {
    NUMBER: 'NUMBER',
    IDENT: 'IDENT',       // bare identifier (SUM, AVG, etc.)
    REF: 'REF',           // {{questionId}}
    OP: 'OP',
    LPAREN: 'LPAREN',
    RPAREN: 'RPAREN',
    COMMA: 'COMMA',
    EOF: 'EOF'
};

function tokenize(input) {
    const tokens = [];
    let i = 0;
    while (i < input.length) {
        const ch = input[i];
        if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r') { i++; continue; }

        if (ch === '{' && input[i + 1] === '{') {
            const end = input.indexOf('}}', i + 2);
            if (end < 0) throw new Error('Unterminated {{ reference');
            const id = input.substring(i + 2, end).trim();
            if (!id) throw new Error('Empty {{ reference');
            tokens.push({ type: TOKEN.REF, value: id });
            i = end + 2;
            continue;
        }

        if (ch >= '0' && ch <= '9' || (ch === '.' && input[i + 1] >= '0' && input[i + 1] <= '9')) {
            let j = i;
            while (j < input.length && ((input[j] >= '0' && input[j] <= '9') || input[j] === '.')) j++;
            tokens.push({ type: TOKEN.NUMBER, value: parseFloat(input.substring(i, j)) });
            i = j;
            continue;
        }

        if ((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || ch === '_') {
            let j = i;
            while (j < input.length && ((input[j] >= 'A' && input[j] <= 'Z') || (input[j] >= 'a' && input[j] <= 'z') || (input[j] >= '0' && input[j] <= '9') || input[j] === '_')) j++;
            tokens.push({ type: TOKEN.IDENT, value: input.substring(i, j).toUpperCase() });
            i = j;
            continue;
        }

        if ('+-*/%'.includes(ch)) { tokens.push({ type: TOKEN.OP, value: ch }); i++; continue; }
        if (ch === '(') { tokens.push({ type: TOKEN.LPAREN }); i++; continue; }
        if (ch === ')') { tokens.push({ type: TOKEN.RPAREN }); i++; continue; }
        if (ch === ',') { tokens.push({ type: TOKEN.COMMA }); i++; continue; }

        throw new Error(`Unexpected character "${ch}" at position ${i}`);
    }
    tokens.push({ type: TOKEN.EOF });
    return tokens;
}

// Recursive descent parser. Grammar:
//   expr   = term  (('+' | '-') term)*
//   term   = unary (('*' | '/' | '%') unary)*
//   unary  = '-' unary | atom
//   atom   = NUMBER | REF | IDENT '(' args ')' | '(' expr ')'
//   args   = (expr (',' expr)*)?

class Parser {
    constructor(tokens) {
        this.tokens = tokens;
        this.pos = 0;
    }
    peek() { return this.tokens[this.pos]; }
    consume() { return this.tokens[this.pos++]; }
    expect(type) {
        const t = this.peek();
        if (t.type !== type) throw new Error(`Expected ${type} at position ${this.pos}, got ${t.type}`);
        return this.consume();
    }
    parseExpr() {
        let left = this.parseTerm();
        while (this.peek().type === TOKEN.OP && (this.peek().value === '+' || this.peek().value === '-')) {
            const op = this.consume().value;
            left = { kind: 'binop', op, left, right: this.parseTerm() };
        }
        return left;
    }
    parseTerm() {
        let left = this.parseUnary();
        while (this.peek().type === TOKEN.OP && (this.peek().value === '*' || this.peek().value === '/' || this.peek().value === '%')) {
            const op = this.consume().value;
            left = { kind: 'binop', op, left, right: this.parseUnary() };
        }
        return left;
    }
    parseUnary() {
        if (this.peek().type === TOKEN.OP && this.peek().value === '-') {
            this.consume();
            return { kind: 'neg', operand: this.parseUnary() };
        }
        return this.parseAtom();
    }
    parseAtom() {
        const t = this.peek();
        if (t.type === TOKEN.NUMBER) { this.consume(); return { kind: 'num', value: t.value }; }
        if (t.type === TOKEN.REF) { this.consume(); return { kind: 'ref', id: t.value }; }
        if (t.type === TOKEN.LPAREN) {
            this.consume();
            const e = this.parseExpr();
            this.expect(TOKEN.RPAREN);
            return e;
        }
        if (t.type === TOKEN.IDENT) {
            const name = this.consume().value;
            this.expect(TOKEN.LPAREN);
            const args = [];
            if (this.peek().type !== TOKEN.RPAREN) {
                args.push(this.parseExpr());
                while (this.peek().type === TOKEN.COMMA) {
                    this.consume();
                    args.push(this.parseExpr());
                }
            }
            this.expect(TOKEN.RPAREN);
            return { kind: 'call', name, args };
        }
        throw new Error(`Unexpected token ${t.type} at position ${this.pos}`);
    }
}

function callFn(name, vals) {
    switch (name) {
        case 'SUM':   return vals.reduce((a, b) => a + b, 0);
        case 'AVG':   return vals.length ? vals.reduce((a, b) => a + b, 0) / vals.length : 0;
        case 'MIN':   return vals.length ? Math.min(...vals) : 0;
        case 'MAX':   return vals.length ? Math.max(...vals) : 0;
        case 'COUNT': return vals.length;
        case 'ABS':   return Math.abs(vals[0] ?? 0);
        case 'ROUND': {
            const x = vals[0] ?? 0;
            const n = Math.trunc(vals[1] ?? 0);
            const factor = Math.pow(10, n);
            return Math.round(x * factor) / factor;
        }
        case 'IF': {
            // IF(cond, then, else). Non-zero is truthy.
            const cond = vals[0] ?? 0;
            return cond ? (vals[1] ?? 0) : (vals[2] ?? 0);
        }
        default:
            throw new Error(`Unknown function ${name}`);
    }
}

function evalNode(node, resolver) {
    switch (node.kind) {
        case 'num': return node.value;
        case 'ref': {
            const raw = resolver(node.id);
            const num = parseFloat(raw);
            return Number.isFinite(num) ? num : 0;
        }
        case 'neg': return -evalNode(node.operand, resolver);
        case 'binop': {
            const l = evalNode(node.left, resolver);
            const r = evalNode(node.right, resolver);
            switch (node.op) {
                case '+': return l + r;
                case '-': return l - r;
                case '*': return l * r;
                case '/': return r === 0 ? NaN : l / r;
                case '%': return r === 0 ? NaN : l % r;
            }
            return 0;
        }
        case 'call': {
            const vals = node.args.map(a => evalNode(a, resolver));
            return callFn(node.name, vals);
        }
    }
    return 0;
}

/**
 * Evaluate a formula. Returns { ok, value, error }.
 * resolver(id) -> string | number | null | undefined: maps a question Id to
 * its current answer. Missing / non-numeric refs evaluate as 0.
 */
export function evaluateFormula(formula, resolver) {
    if (!formula || !formula.trim()) {
        return { ok: true, value: '' };
    }
    try {
        const tokens = tokenize(formula);
        const ast = new Parser(tokens).parseExpr();
        const result = evalNode(ast, resolver);
        if (typeof result !== 'number' || !Number.isFinite(result)) {
            return { ok: false, value: '', error: 'Result is not a finite number' };
        }
        return { ok: true, value: result };
    } catch (e) {
        return { ok: false, value: '', error: e.message || String(e) };
    }
}

/**
 * Find every {{questionId}} reference in a formula. Used by the renderer to
 * subscribe a Calculation question to changes in its dependencies.
 */
export function extractReferences(formula) {
    if (!formula) return [];
    const out = [];
    const re = /\{\{\s*([^}]+?)\s*\}\}/g;
    let m;
    while ((m = re.exec(formula)) !== null) {
        if (m[1]) out.push(m[1]);
    }
    return out;
}

/**
 * Format the numeric result per the question's Calculation_Result_Format__c.
 */
export function formatResult(value, format) {
    if (value === '' || value === null || value === undefined || !Number.isFinite(value)) {
        return '';
    }
    switch (format) {
        case 'Integer':  return String(Math.round(value));
        case 'Currency': {
            try {
                return new Intl.NumberFormat(undefined, { style: 'currency', currency: 'USD' }).format(value);
            } catch (e) {
                return value.toFixed(2);
            }
        }
        case 'Percent':  return (value * 100).toFixed(2) + '%';
        case 'Decimal':
        default:         return String(value);
    }
}
