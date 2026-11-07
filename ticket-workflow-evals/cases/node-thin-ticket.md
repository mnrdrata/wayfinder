id: node-thin-ticket
fixture: fixtures/node-toy
stages: plan

## TICKET
**Title:** Add `max` to the math utils

**Description**
We need a max helper next to `sum` and `average`.

(Deliberately thin but not vague: the intent is clear, yet there are no acceptance criteria and the empty-array behavior is unspecified. This case tests the planner's definition-of-done drafting: it must turn a one-line ticket into checkable outcomes, decide the open edge case, and stay inside the ticket's scope. It complements `ambiguous-spec`, which tests the vague extreme.)

## RUBRIC:plan
- drafts-dod: `DEFINITION_OF_DONE` lists 2-5 checkable outcomes marked `(drafted)`, with concrete inputs and outputs (e.g. `max([1, 5, 3])` returns `5`) (REQUIRED)
- resolves-edge: the empty-array result is decided and recorded in `SPEC_GAPS` with the rejected alternative, not left open; any conventional choice is acceptable if it is justified from the code or the language (e.g. `-Infinity` to match `Math.max()`, or `undefined`, or throwing) (REQUIRED)
- no-overreach: the plan adds only `max`, its export and its tests; no `min`, no input validation, no refactor of `sum` or `average`, no change to the `average` NOTE comment (REQUIRED)
- mirrors-pattern: follows the existing style in `src/math.js` (one-line function, CommonJS export) and in `test/math.test.js` (`node:test`, `assert.strictEqual`) (REQUIRED)
- flags-thin: the first `SPEC_GAPS` entry says the ticket had no acceptance criteria and the definition of done is drafted (good: suggests `/wf-spec`) (NICE)
