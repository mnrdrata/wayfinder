---
description: Decide whether a built ticket needs a customer help article (new or update) and a CS enablement guide, then write them. Files a help-article request for the technical writing team in Linear, drafted to the UX content guidelines, and publishes the enablement guide in Notion. Runs after acceptance evidence in wf-run-ac, or on its own.
argument-hint: <ticket-id> [--assess-only]
allowed-tools: Task, Bash, Read
---

# /wf-docs

Documentation for a feature that just shipped. Most tickets need none, and this says so and stops. When a ticket does need docs:

- **Help article.** A new feature, page, route, navigation entry or flow gets a request for a new article. A change that makes an existing article wrong gets a request to update it. Either way the technical writing team picks it up in Linear.
- **CS enablement guide.** Required whenever there's a help article. Also required for a significant behavior change Support will see, even when customers need no article.

Never asks questions mid-run. Never changes a ticket's status.

## Arguments

`$ARGUMENTS` holds a ticket identifier and an optional `--assess-only`. With `--assess-only`, print the verdict and write nothing.

## 0. Config

Read the `docs` block of `~/.claude/wf-repos.json` (`wf-repos.example.json` documents each key). If there's no `docs` block, print `WF_DOCS <ticket> skipped no-docs-config` and stop. Resolve these to absolute paths:

- `content_coach.skill`: when it's relative, it's relative to the checkout of the repo named in `content_coach.repo`, from `repos`
- `writing_guide`: a glob, so expand it with `ls`

A path that doesn't exist becomes `missing`. The builder then works from the example documents alone, and says so.

## 1. Gather (concurrently)

- `wf-linear`: fetch the ticket. If it's a repo sub-issue, use its parent from here on. Return:
  - title, description, URL, assignee and project
  - every sub-issue, with its PR links
  - all comments, including the acceptance-evidence comment with its image markdown intact
- `wf-github`: once the PR URLs are known, run `PR_DIFF` for each, plus each PR's title and body.

A diff over about 3,000 lines is trimmed. Keep routes, navigation, UI copy and strings, permissions, error messages and migrations, and list the files that were left out.

No PRs means nothing shipped. Print `WF_DOCS <ticket> skipped no-prs` and stop.

## 2. Assess

Spawn `wf-docs-assessor` with `TICKET`, `PRS` and `EVIDENCE`. If both verdicts are `none` and `no`, print the result line and stop. Post nothing: a "no docs needed" comment on every ticket is noise.

With `--assess-only`, print the assessor's output and the result line, then stop.

## 3. Build

Spawn `wf-docs-builder` with:

- `VERDICT`, the assessor's full output
- `TICKET`: identifier, title, URL, project (or `none`), assignee and PR URLs
- `DOCS_CONFIG`, with paths resolved

The builder writes to Linear and Notion directly, and updates its own earlier output on a re-run.

## Result

End your final message with exactly one line:

```
WF_DOCS <ticket> help=<new|update|none> enablement=<yes|no> <request-url or -> <guide-url or ->
```

On a failure, put the reason before that line. Keep the line itself, with `-` for what wasn't written.
