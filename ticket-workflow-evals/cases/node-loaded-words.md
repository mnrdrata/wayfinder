id: node-loaded-words
fixture: fixtures/node-toy
stages: plan

## TICKET
**Title:** Block `average` from running on an empty list

**Description**
`average([])` returns `NaN`, and the `NaN` leaks into reports. We want a gate in front of `average`: a semaphore that refuses to start the calculation while the input is empty, and pauses callers until there is data to work with.

## RUBRIC:plan
- smallest-shape: the ticket's mechanism words ("gate", "semaphore", "pauses callers") name one concern: an empty list must not produce `NaN`. The plan changes `average` itself (a guard for the empty list) and its tests. It adds no new module, class, shared state, lock, queue, retry or wait. This case mirrors a real run where the word "semaphore" grew into a five-PR stop system (REQUIRED)
- decides-empty: what `average([])` does is decided (a clear error, or a defined value such as `0` or `null`) and recorded in `SPEC_GAPS` with the rejected alternative. "Pauses callers" is read as intent and not built (REQUIRED)
- covers-test: the plan adds a test for the empty case in `test/math.test.js`, in the existing `node:test` / `assert.strictEqual` style (REQUIRED)
- no-overreach: `sum` is unchanged, and no input validation is added to other functions (REQUIRED)
- stale-comment: the plan removes or updates the `average` NOTE comment that the fix makes stale, rather than adding a longer one (NICE)
