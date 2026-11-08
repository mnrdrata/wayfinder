Prove the acceptance criteria of Linear ticket {{TICKET}} with evidence, and post the result as one comment on {{TICKET}}. Work hands-off: never ask a question, and when something is unclear, take the safe reading and say so in the comment.

The work is already built. These pull requests carry it:

{{PRS}}

## 1. Find what has to be proven

- Read {{TICKET}} in Linear, including its comments. If it has sub-issues, read each one and its comments too.
- Each acceptance criterion is something to prove. Find them in, in order of preference:
  1. a "Definition of done" section in a `🤖 /wf opened` comment
  2. a "Done when" or "Acceptance criteria" section in the description
  3. the ticket's stated outcome, when it has neither. In that case, write the checks you'll run at the top of the comment, marked as drafted.
- A criterion that can't be checked in this environment (a production-only integration, an external provider) stays in the comment as "not checked here", with the reason.

## 2. Deploy every pull request together

- Check out each PR's branch in its repo. They're meant to run together, so a frontend PR runs against its backend PR, not against `release` or `main`.
- Start the stack with this environment's own tooling (its deploy skill or scripts). Regenerate any client the frontend builds from the backend's API, from the backend branch.
- Before you test, confirm the deployed commit of each repo matches its PR's head commit. Put those commits in the comment.

## 3. Collect evidence for each criterion

Pick the evidence that shows the behaviour, not just that code exists:

- **Something a user sees:** a screenshot of the state the criterion describes. For a flow, a sequence or a timing, also record a short animated WebP. Use this environment's screenshot and video skill when it has one (on Starfolk: `web-ui-screenshots-and-videos`). Capture at 1280x800, device scale factor 2, reduced motion.
- **An API:** a small table of each request (method, path, the input that matters) and its status code and the key part of the body. Use curl or the app's client.
- **Background or data behaviour:** the log line or database query that shows it, trimmed to what proves the point.
- **Prove the failure path too** when a criterion is about errors: force the failure (a bad token, a missing dependency, an invalid input), show it, then show recovery when the criterion covers it.

Rules for every capture:

- **Write all capture scripts, screenshots and recordings under `wf-evidence/` in the checkout's git directory** (`git rev-parse --absolute-git-dir`; `.git` may be a file pointing elsewhere, as on Starfolk). That folder belongs to the checkout, so you can read your own captures back without a permission prompt, and git never commits it. Don't use `~/.devbox/tmp` or `/tmp` for anything you need to read back.
- **Look at every screenshot before you post it.** A page that answered 200 can still be blank, half-rendered or showing the wrong state.
- Use test data only. Never capture real customer data, tokens or secrets.

## 4. Post one complete comment on {{TICKET}}

Embed the images and animations inline, uploaded to Linear, so the comment reads on its own. Attach a zip only when the files together are over about 10 MB; a ticket split into sub-issues rarely needs one. Use this shape:

```
## Acceptance test results <✅ all pass | ❌ N of M fail | ⚠️ partly checked>

<one line: what the ticket delivers, in plain words>

**Built:** <each PR as a link, with its repo, and whether CI is green>
**Tested on:** <environment, and the deployed commit of each repo>

**1. <criterion, as the ticket states it>** <✅ | ❌ | not checked here>
<the evidence: table, screenshot, animation or log, then one sentence on what it shows>

**2. …**

**Timing** (only when the ticket asks a timing question)

**Observations (not blockers)**
- <anything odd you noticed that the criteria don't cover>

🧭 Co-authored by [wayfinder](https://github.com/kyuss/wayfinder)
```

Keep the prose short. The evidence should carry the proof.

## 5. Don't change the work

You prove the work; you don't fix it. When a criterion fails, record it as ❌ with the evidence and a one-line guess at the cause, and leave the code, the PRs and the ticket states alone. A human decides what happens next.

## 6. Finish

Write one line to the file `{{RESULT_FILE}}`, creating its folder if needed:

```
RESULT <pass | fail | partial> <URL of the comment you posted>
```

Use `pass` when every criterion passed, `fail` when any failed, and `partial` when none failed but some weren't checked. If you couldn't post the comment at all, write `RESULT error none` and end with the reason. The script that started you reads this file to know you're done. Also end your final message with the same `RESULT` line, as a fallback if the file can't be read.
