id: chain-plan
fixture: fixtures/node-toy
stages: plan
chain: TOY-1, TOY-2

## TICKET
### TOY-1
**Title:** Add a `product(arr)` helper to the math utils

**Description**
Add `product(arr)` next to `sum`/`average` in `src/math.js`. It returns the product of all numbers in the array.

## Acceptance criteria
- [ ] `product([2,3,4])` returns `24`
- [ ] `product([])` returns `1`
- [ ] A test in `test/math.test.js` covers both cases
- [ ] `product` is exported from `src/math.js`

### TOY-2 (blocked by TOY-1)
**Title:** Add `geometricMean(arr)` built on `product`

**Description**
Add `geometricMean(arr)` to `src/math.js`. It returns the nth root of the product of n numbers, using the `product` helper from TOY-1.

## Acceptance criteria
- [ ] `geometricMean([2,8])` returns `4`
- [ ] `geometricMean([])` returns `NaN`, matching how `average([])` behaves today
- [ ] A test in `test/math.test.js` covers both cases
- [ ] `geometricMean` is exported from `src/math.js`

## RUBRIC:plan
- chain-shape: output is `STATUS: CHAIN_PLAN` with one shared `CONTEXT_PACK`, then a TOY-1 section followed by a TOY-2 section (REQUIRED)
- no-duplicate-work: the TOY-2 plan calls the existing `product` from TOY-1 and does not add, re-implement or re-plan `product` (REQUIRED)
- no-pull-forward: the TOY-1 plan does not add `geometricMean` or any TOY-2 work (REQUIRED)
- covers-criteria: each ticket's steps and tests map to all 4 of its acceptance criteria, including the empty-array cases (REQUIRED)
- surgical: only `src/math.js` and `test/math.test.js` change; no speculative helpers or refactors (REQUIRED)
- no-false-blockers: `UPSTREAM_BLOCKERS` is `none` for both tickets (the dependency is inside the chain, not upstream)
