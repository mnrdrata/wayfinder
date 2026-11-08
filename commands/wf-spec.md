---
description: Interactively refine one or more Linear tickets into implementation-ready specs — posted as a marked comment on each ticket, with a short Why/What/Success-criteria brief written to its description — or, for research/spike tickets, record a decision written back to the description. Optional: /wf drafts its own definition of done, so use this for vague or high-stakes tickets you want agreed before building.
argument-hint: "[--inline|--linear] [ticket-id...]  (linear mode runs tickets in parallel; no ids + linear = resume everything awaiting answers)"
allowed-tools: Task, Bash, Read, Edit, AskUserQuestion
---

# /wf-spec

Refine each ticket into a spec that carries enough information for the autonomous /wf workflow to go A→Z without further human input. This phase IS interactive — the only question is **where** the clarifying questions get answered (see *Question mode* below).

You are the orchestrator. Do not write specs or touch Linear yourself — delegate. **How many tickets you process at once depends on `MODE`** — see *Processing order* below.

## Up front (once)

`READY_STATE = "Ready for Development"` (`wf-linear` resolves it to the team's state by synonym, falling back to Todo on teams without it — most Drata teams). "Needs Answers" likewise resolves to Blocked at Drata. There is no generated repo manual: `wf-spec-builder` reads the repo's own `CLAUDE.md`/`AGENTS.md` itself.

## Entry routing (parse `$ARGUMENTS`)

Resolve two things before processing tickets: the **question mode** and the **ticket list**.

**Question mode — where clarifying questions get answered.** Resolve by precedence, first hit wins, and call the result `MODE`:
1. **Flag override** (this run only): `--inline` → `MODE=inline`; `--linear` → `MODE=linear`.
2. **Built-in default:** else `MODE=inline`.

- `MODE=inline` — put clarifying questions to **you** in the terminal via AskUserQuestion (the solo-dev path; needs no special Linear state).
- `MODE=linear` — post the questions as a Linear **comment** and park the ticket in *Needs Answers* for a teammate to answer asynchronously in the Linear UI (no terminal).

**Ticket ids** = the remaining tokens after removing any `--inline`/`--linear` flag.
- **Ids given** → process exactly those.
- **No ids** → **sweep mode** (only meaningful under `MODE=linear`): spawn `wf-linear` with intent `LIST_BY_STATUS "Needs Answers"` (your own tickets only; Blocked at Drata) and process every returned identifier. Tickets can be in that state for reasons unrelated to spec questions, so in sweep mode a ticket whose `READ_ANSWERS` returns `NO_PENDING` is **skipped**, never spec'd. If it returns `none`, tell the user nothing is awaiting answers and stop. Under `MODE=inline` there's nothing to resume — tell the user to pass ticket ids and stop.

## Processing order

`MODE` decides concurrency. The ticket steps below are written per-ticket; this governs how they're scheduled across the batch:

- **`MODE=inline` — strictly sequential.** Finish one ticket (steps 1–6) before starting the next. Its clarifying questions are a live terminal conversation; interleaving them would be confusing. (Unchanged behavior.)
- **`MODE=linear` — parallel by default.** Linear mode never blocks on you at all, so fan the whole batch out end-to-end: run steps **1–5** for **up to 3 tickets concurrently** (same cap as `/wf`). A ticket whose builder returns `NEEDS_INPUT` posts its questions and parks itself (step 4's linear branch) with no interaction; a ticket that returns `SPEC`/`DECISION` **persists directly with no confirmation** (step 5 — linear mode never prompts you in the terminal). There is no serial touchpoint. This is read-only work (no worktrees), so concurrent `wf-spec-builder`/`wf-linear`/`wf-github` spawns don't contend.
  - **Order by intra-batch dependencies.** If one batch ticket `blocks` / is `blocked-by` another *in the same batch* (e.g. a spike and the ticket it unblocks), run the dependency in an **earlier wave** so its decision/spec is persisted before the dependent's step-3 `RELATED_DECISIONS` pull runs. Independent tickets share the first wave; when the batch has no internal links — the common case — it's a single wave.

## Per ticket

1. **Fetch.** Spawn `wf-linear` with intent: `FETCH <identifier>`. Capture the returned identifier, title, current state, description, comments, and the `ATTACHMENTS` list. **If its comments include one whose first line starts with `🤖 Spec questions`, this ticket is a resume** — it was parked earlier with questions posted to Linear. Detect this from the comments, not the state: most teams have no *Needs Answers* state (at Drata parked tickets sit in Blocked, or keep their state). Remember this; step 4 branches on it.

2. **Ingest design handoffs (if any).** If `ATTACHMENTS` is not `none`, download each **promptly** — the signed hrefs expire ~5 min after the fetch. For each entry, run `~/.claude/bin/wf-fetch-handoff <handoff-dir> "<href>" <size-bytes>` where `<handoff-dir>` is a fresh scratch dir for this ticket (e.g. `$(mktemp -d)/<identifier>-handoff`). The helper validates the host/size, unpacks zips safely, and prints the unpacked path. Collect the printed paths as `HANDOFF` (a dir, or list of dirs/files). If the helper fails (expired link, etc.), note it and continue with `HANDOFF=none` — ingestion is best-effort and never blocks specing.

3. **Gather context (GitHub + related tickets).** Spawn the two fetches below **in one message** so they run concurrently — they're independent of each other.
   - Spawn `wf-github`: `PR_HISTORY <keywords from the ticket title/description>` → a digest of how related work was done/merged here. Call the result `PR_HISTORY`.
   - Spawn `wf-linear`: `RELATED <identifier>` → a compact digest of explicitly-linked and sibling tickets (prior decisions, adjacent scope) that PR history won't surface. Call the result `RELATED_TICKETS` (or `none`). This is reference context only — it never blocks; if it errors, carry `RELATED_TICKETS=none` and move on.
   - **Pull recorded decisions.** Scan `RELATED_TICKETS` for any line marked `[DECISION]` (a linked research/spike ticket that has a recorded decision — usually a `blocking`/`blocked-by` dependency of this ticket). For each such id, spawn `wf-linear` `FETCH <id>` and extract its `## Decision` section from the returned description. Collect these as `RELATED_DECISIONS` (one block per source id: the id + its `## Decision` section), or `none`. These are resolved facts the spec must build on, not re-litigate. Best-effort: if a fetch errors, note it and carry on with the decisions you did get.

4. **Refine.** Spawn `wf-spec-builder`, passing the full fetched ticket content, the `PR_HISTORY` digest, the `RELATED_TICKETS` digest, the `RELATED_DECISIONS` digest, **and** `HANDOFF` (the local path(s), or `none`) — plus, on a resume, an `ANSWERS:` section (see below). It explores the codebase and reads any handoff as **reference-only** visual/behavioral source of truth. **It cannot reach the user** (`AskUserQuestion` doesn't surface inside a subagent), so it returns `STATUS: NEEDS_INPUT` (question blocks: `header` / `question` / `multiSelect` / `options`, recommended option marked), `STATUS: SPEC` (finished implementation spec markdown), or — for a research/spike ticket — `STATUS: DECISION` (the full new description with a `## Decision` section appended). The builder is **mode-agnostic** on questions — it always just returns them; `MODE` only decides what *you* do with them.

   **Resume entry — if step 1 flagged this ticket as a resume:** before spawning the builder, spawn `wf-linear` with intent `READ_ANSWERS <identifier>`.
   - `QUESTIONS_STATUS: AWAITING` → the teammate hasn't replied yet. Report "still awaiting answers" and leave it parked — don't spawn the builder. (In linear-parallel mode this ticket's task is simply done.)
   - `QUESTIONS_STATUS: NO_PENDING` → no question comment found; in sweep mode skip the ticket (it is blocked for some other reason), otherwise treat as a fresh spawn (no `ANSWERS`).
   - `QUESTIONS_STATUS: ANSWERED` → build the `ANSWERS:` section from the reply. The `QUESTIONS` body it returns is the exact comment you posted (numbered questions, lettered options, ✅ on the recommended). Map the teammate's free-text reply onto it: `all recommended` → every ✅ option; `1: B` → question 1's option B label; option text or clear paraphrase → that option; genuine free-text that matches no option → pass it verbatim (an "Other" answer). If a question is left unanswered or is truly ambiguous, fall back to its recommended option **and note it in the run summary** so you can flag it to the user. Emit `ANSWERS:` as one line per question: `Qn (<question text>): <chosen option label(s) verbatim>[ — <free-text>]`. Then spawn the builder with the base inputs **plus** this `ANSWERS:` section.

   **Handling the builder's return (both fresh and resume):**
   - **`STATUS: SPEC`** — strip the status line and split the body on the two sentinel lines into `TICKET_DESCRIPTION` (before `--- SPEC ---`) and `SPEC` (after it); go to step 5 (persist as a spec). (A clear-enough ticket returns this on the first fresh spawn with no questions — fine, not an error. No questions comment is posted and the ticket is never parked.)
   - **`STATUS: DECISION`** — a research/spike ticket, resolved. The body is the full new description (original preserved + an appended `## Decision` section). Strip the status line; go to step 5 (persist in **decision mode**).
   - **`STATUS: NEEDS_INPUT`** — a genuine decision is open:
     - **`MODE=inline`** → put the blocks to the user yourself via AskUserQuestion (you're the orchestrator — it works here): map each block to a question, options in the given order with the `(recommended)` one first and labeled "(Recommended)". Re-spawn the builder with the same inputs plus the `ANSWERS:` section. Repeat until it returns a spec (1–2 rounds is normal; after ~3, ask the user whether to push through with defaults).
     - **`MODE=linear`** → **post the questions to Linear and park** — do NOT block or ask in the terminal:
       1. Render **all** the builder's question blocks into ONE consolidated markdown comment, in exactly this shape (the first line is the marker `READ_ANSWERS` keys on — keep it verbatim):
          ```
          🤖 Spec questions — please reply in a comment below

          Hi! Before we build **<title>** (<identifier>) a few quick questions — reply in a comment. Give the option letter for each, or just reply **all recommended** to accept every ✅.

          **1. <question text>**   ← add " *(pick any that apply)*" if the block is multiSelect
          - A) <option label> ✅ recommended
          - B) <option label>
          - C) <option label>

          **2. <question text>**
          - A) <option label> ✅ recommended
          - B) <option label>

          _Reply like:_ `1: B, 2: A and C` _— or just_ `all recommended`.
          ```
          Number questions in the builder's order; letter the options in the builder's order; put `✅ recommended` on the option the builder tagged `(recommended)`.
       2. Spawn `wf-linear` `POST_COMMENT <identifier>` with that markdown.
       3. Spawn `wf-linear` `SET_STATUS <identifier> "Needs Answers"` (Blocked at Drata). If it returns `ERROR: no workflow state matches`, leave the state: the question comment alone marks the ticket as parked.
       4. Park this ticket: report `awaiting answers` (under linear-parallel it's just one finished task in the fan-out). The teammate answers in Linear; a later `/wf-spec` run (with this id, or no ids to sweep) resumes it via the READ_ANSWERS path above.

5. **Persist.** Write the finished output back to the ticket. **`MODE=inline`** gates the write behind one AskUserQuestion (you're at the terminal); **`MODE=linear`** persists **directly with no confirmation** — the async/no-terminal mode never prompts you; the teammate reviews the written spec/decision in Linear. Two flavors:

   **Spec (`STATUS: SPEC`)** — the builder's output is already split on the two sentinels into `TICKET_DESCRIPTION` (the brief) and `SPEC` (the full spec). Compose, then persist in this exact order:
   - **(0) Compose** `NEW_DESCRIPTION` = the `TICKET_DESCRIPTION` block + a blank line + the verbatim trailer `_Full implementation spec: see the latest **🤖 Implementation spec** comment on this ticket._` + — only if step 1's fetched description contained any `<linear-embed node-type="file">…</linear-embed>` blocks — a `## Design handoff` heading placed after the trailer with those blocks copied verbatim (omit the heading entirely when there are none). Compose `SPEC_COMMENT` = the exact line `🤖 Implementation spec — generated by /wf-spec`, a blank line, then the `SPEC` block verbatim.
   - **(1)** Spawn `wf-linear` `POST_COMMENT <identifier>` with `SPEC_COMMENT` — **always append a new comment; a prior spec comment is never modified or removed** (latest wins, by design).
   - **(2)** Spawn `wf-linear` `UPDATE_DESCRIPTION <identifier>` with `NEW_DESCRIPTION`.
   - **(3)** Spawn `wf-linear` `SET_STATUS <identifier> "<READY_STATE>"` to mark the ticket spec-ready for `/wf`.
   - **Failure semantics:** if (1) returns `ERROR`, do **not** run (2) or (3) — surface the error and leave the ticket unchanged (nothing to fall back to yet). If (2) returns `ERROR`, the spec comment from (1) is already the source of truth — surface the error and still run (3). If (3) returns `ERROR` (e.g. the team has no such state), surface it but treat (1)+(2) as the success — don't undo them.
   - **`MODE=inline`** → one confirmation gates all three calls: "Post the spec comment and refresh the description on <identifier>?" (Yes / Edit / Skip). **Yes** → run (1)–(3). **Edit** → relay the user's tweaks back to `wf-spec-builder` (re-spawn with the prior spec + requested changes; it returns both sections again), then re-confirm. **Skip** → leave the ticket unchanged — neither write happens.
   - **`MODE=linear`** → run (1)–(3) directly, no confirmation.

   **Decision (`STATUS: DECISION`)** — the persist action: spawn `wf-linear` with intent `UPDATE_DESCRIPTION <identifier>` and the returned description (original + `## Decision` section) as the new description. **Do NOT set Ready-for-Development** — a resolved spike has nothing to build; leave its status unchanged. The recorded decision now reaches any dependent ticket via the `RELATED_DECISIONS` pull (step 3) and folds into that ticket's own spec when it's refined.
   - **`MODE=inline`** → confirm "Record this decision on <identifier>?" (Yes / Edit / Skip) first. **Yes** → run the persist action, then tell the user the spike is decided and that they close it (Done) in Linear when satisfied. **Edit** → relay the user's tweaks back to `wf-spec-builder` and re-confirm. **Skip** → leave the ticket unchanged; note it.
   - **`MODE=linear`** → run the persist action directly.

6. Status moves to **Ready for Development** (Todo on teams without it) only when the **spec comment** was posted (step 5 spec → Yes, call (1) succeeded) — this also lifts a resumed ticket out of *Needs Answers*/Blocked. A **decision** written for a research/spike ticket does **not** transition status (the workflow never auto-completes; the human closes the spike). Tickets **parked** for answers sit in *Needs Answers*; tickets that were skipped — or edited but not yet written — keep their current status; don't transition them.

## After all tickets

Print a compact summary: each identifier → `spec written` / `decision recorded` / `awaiting answers` / `still awaiting` / `skipped`. For any `decision recorded`, note the spike is resolved and the user closes it in Linear when satisfied. If any ticket is `awaiting answers`, remind the user that their teammate answers the question comment in Linear, and that re-running `/wf-spec <id>` — or `/wf-spec` with no ids to sweep every parked ticket — resumes it. For tickets with a spec written, remind them they can now run `/wf <ids>`. Also surface any answers you had to default (from an ambiguous/blank reply) so the user can correct them.

## Notes
- If `wf-linear` returns `ERROR`, surface it plainly and ask the user how to proceed — don't guess ticket data.
- Keep your own prose terse — your job in the loop is to relay the builder's questions to the user and its spec back. Relay the questions directly, without explaining why they're coming from you.
