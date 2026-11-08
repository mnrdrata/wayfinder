id: node-review-comment
fixture: fixtures/node-toy
stages: review

## TICKET
**Title:** `average([])` returns NaN — guard the empty case

**Description**
## Summary
`average(arr)` in `src/math.js` divides by `arr.length`, so `average([])` returns `NaN`. It should return `0` for an empty array.

## Acceptance criteria
- [ ] `average([])` returns `0`
- [ ] `average([2,4])` still returns `3`
- [ ] A regression test covers the empty case and passes

## MUTATION
Simulates an executor diff that is correct but bloated. One planted flaw:
1. **Comment bloat** — a 6-line comment block above `average` parks ticket history, the options that were discussed, accepted-risk analysis and a runbook-style instruction. That material belongs in the PR body or the ticket. The guard, the test, and the removal of the stale NOTE comment are all correct.

This case guards the reviewer's comment rule from the other side: `node-review-bug` checks that an untouched comment is NOT blocking; this case checks that a comment the diff adds IS blocking.

### file: src/math.js
```js
function sum(arr) { return arr.reduce((a, b) => a + b, 0); }
// average(): hardened for the "average([]) returns NaN" ticket.
// History: it used to divide by arr.length unconditionally, so empty input gave 0 / 0 = NaN.
// Options discussed in review: throw a RangeError, return null, or return 0.
// We chose 0 to match sum([]) === 0, even though callers can't tell "empty" from a real 0.
// Accepted risk: a caller that relied on NaN now silently gets 0.
// If this contract changes, update test/math.test.js and tell every consumer first.
function average(arr) { return arr.length === 0 ? 0 : sum(arr) / arr.length; }
module.exports = { sum, average };
```

### file: test/math.test.js
```js
const test = require('node:test');
const assert = require('node:assert');
const { sum, average } = require('../src/math');
test('sum adds numbers', () => { assert.strictEqual(sum([1, 2, 3]), 6); });
test('average of [2,4] is 3', () => { assert.strictEqual(average([2, 4]), 3); });
test('average of empty array is 0', () => { assert.strictEqual(average([]), 0); });
```

## RUBRIC:review
- catches-comment-bloat: flags the added multi-line comment block as BLOCKING because it parks history, rationale, or accepted risk that belongs in the PR or ticket; good: offers a trimmed version of at most 1-3 lines, or none (REQUIRED)
- verdict: `CHANGES_REQUIRED` (REQUIRED)
- accepts-correct-fix: raises no BLOCKING item against the `arr.length === 0` guard, the strict empty-case test, or the removal of the stale NOTE comment; all three are correct (REQUIRED)
- no-noise: no speculative or style-only BLOCKING items beyond the planted comment (REQUIRED)
