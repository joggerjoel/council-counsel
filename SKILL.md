---
name: council
description: Use when the user asks for a "council", "counsel", "council-counsel", multi-model review, second opinion, cross-model verification, or an independent panel to review a plan, design, diff, PR, or decision — routing the same question to external model CLIs (codex, gemini, cursor, cortex) alongside Claude and reconciling their verdicts.
---

# Council

## Overview

Get independent verdicts from multiple frontier models on the same artifact, then reconcile. Claude orchestrates: fan the question out to the authenticated external CLIs, collect each verdict verbatim, and synthesize — surfacing agreements as high-confidence and disagreements as the things to look at.

**Core principle:** independent first, reconciled second. Never let one model see another's answer before it forms its own, or you get anchoring instead of a second opinion.

## Reality-gated roster — only functional members participate

**Never install a CLI to make it join. Never use API keys — subscription/login sessions only.** A member participates only if it is _installed → logged in → functionally returns text_. Run `scripts/probe.sh` first; it reports three states (⛔ not installed · ❌ installed-not-functional · ✅ functional) and never installs anything.

**Priority order (ask the strongest first):** **1) Claude (highest model)** → **2) codex (highest model, high reasoning)** → 3) gemini. Claude + codex alone is a valid council; gemini adds breadth. **cursor and cortex are currently OUT** (see below) — the functional council is **Claude + codex + gemini**.

| Member                       | Invocation (non-interactive)                                             | Status (verified 2026-07-19)       | Limits / notes                                                                                                                                                                          |
| ---------------------------- | ------------------------------------------------------------------------ | ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Claude** (me)              | native, highest model + high/max effort                                  | ✅ functional — anchor + judge     | session limits                                                                                                                                                                          |
| **codex** `gpt-5.6-sol`      | `codex exec --skip-git-repo-check -c model_reasoning_effort=high 'P'`    | ✅ functional (~8s)                | ChatGPT login. **Rolling 5h + weekly cap** — scarcest; 1–2 calls/run                                                                                                                    |
| **gemini** `2.5-flash`/`pro` | `GEMINI_CLI_TRUST_WORKSPACE=true gemini -p 'P' --model gemini-2.5-flash` | ✅ functional (~4s idle)           | API key. **RPM/RPD quota → 429 triggers 30s+ auto-retries** that look like a hang; the watchdog caps it.                                                                                |
| **cursor** (`agent`)         | `agent -p 'P' --output-format text --model auto`                         | ❌ **context-blocked**             | Interactive `agent login` works, but headless `agent -p` sees "Not logged in" from the automation shell (session in keychain/app, unreachable). Would need `CURSOR_API_KEY` — declined. |
| **cortex**                   | `cortex exec 'P'`                                                        | ❌ **license-blocked (permanent)** | `cortex exec` not permitted under the current Snowflake license. Do not retry.                                                                                                          |

CLIs live at `~/.local/bin/{codex,agent,cortex}` and `~/.nvm/.../bin/gemini`. Auth drifts — re-probe before every real run. Each script bounds every member with a `perl alarm` watchdog so a 429-retry storm or auth stall can't hang the fan-out.

## Role → model assignment

Shift each lens to the model whose strength fits it; fall back to Claude if that model isn't functional. Only assign roles to ✅-functional members.

| Review role / lens                        | Best-fit model                | Why                                   |
| ----------------------------------------- | ----------------------------- | ------------------------------------- |
| Judge / aggregator / orchestrator         | **Claude**                    | reconciles, ranks, owns the standards |
| Correctness / bug-logic (careful tracing) | **Claude** (highest)          | deliberate step-through               |
| Security / red-team (adversarial)         | **codex** (high reasoning)    | strongest adversarial mindset         |
| Performance / scaling (systems thinking)  | **codex** or **gemini**       | algorithmic vs. big-picture           |
| Architecture / design breadth             | **gemini** (large context)    | wide-context sweep                    |
| Maintainability / codebase consistency    | **Claude**                    | has repo access via subagents         |
| Test coverage / gaps                      | **Claude** `pr-test-analyzer` | repo-aware test reasoning             |

## When to use

- "convene the council", "get counsel", "second opinion", "what does codex/gemini think", "cross-check this plan"
- Before a hard-to-reverse decision (architecture, migration, security) where one model's blind spot is costly.
- NOT for quick factual lookups or where the user wants only Claude.

## Default protocol (budget-aware)

**One fan-out round, then reconcile.** codex's 5h window makes N-round loops dangerous.

1. **Frame once.** Write a single self-contained prompt: the artifact (paste content or path the CLI can read) + a sharp ask ("Review this plan. List the top risks, wrong assumptions, and missing cases. Be specific; cite lines."). Same prompt to every member.
2. **Fan out concurrently.** Run `scripts/council.sh -f <file>` (or `-p '<prompt>'`). It calls only authenticated members in parallel, writing each verdict to `outputs/<member>.md`. gemini-flash is cheap — use freely; codex counts against the window.
3. **Reconcile (Claude).** Read every verdict. Produce: **consensus** (raised by ≥2 → high confidence), **split** (one model only → flag for judgment), **Claude's own take**. Attribute each point to its source. Do not average — a lone correct dissent beats a wrong majority.
4. **Re-query only on genuine disagreement** — one targeted follow-up to the disagreeing member, not another full round.

## Convergence: stop at 90–95%, not 100%

The goal is **~90–95% agreement with a preserved 5–10% residual** — never forced unanimity. That residual disagreement is the highest-signal output of the whole exercise: it's where a real risk, an unstated assumption, or a genuine judgment call lives. Report it, don't dissolve it.

- **Converged (≥~90% agree):** stop. Ship the consensus + explicitly list the 5–10% each model flagged that the others didn't. Don't spend another codex call chasing the last few percent.
- **Diverged (<~90%, models materially disagree on something that matters):** one targeted re-query to resolve _that specific_ point — then stop regardless. Forcing to zero disagreement usually means one model capitulated to another (anchoring), which is worse than an honest split.
- The convergence target doubles as a **rate-limit budget**: stopping at 90–95% is what keeps a council inside codex's 5h window.

## Advanced: role-specialized lenses (optional)

One agent covering every angle goes broad, not deep — it defaults to the easy comment and misses the high-impact risk. So for a heavy review, replace the single "review this" prompt with parallel **specialized lenses**, each with one job and one definition of done:

- bug/logic (does it work? how does it fail?) · security (adversarial mindset) · performance/scaling (systems thinking) · maintainability/consistency-with-codebase · tests/coverage gaps

Run one lens per member, or per Claude review subagent (`code-reviewer`, `silent-failure-hunter`, `type-design-analyzer`, `pr-test-analyzer`). **Every finding answers three things: what is the issue, why it matters, what to do next.** Then a **judge/aggregator** (Claude) asks the single question _"which few issues actually change the risk of this PR?"_ — merge overlapping points, drop low-impact nits, keep only what's tied to a real failure path. Output a ranked plan, not a wall of feedback. Multi-pass beats one monolithic review, but each lens is a call — apply the same convergence + budget discipline. Your role is orchestrator: define what "secure" and "clean" mean; the agents enforce it.

## Beyond review: fleet execution (parallel decomposition)

The council fans one question to many models and **converges** (review). The inverse also pays off: after a **decomposer** splits work into independent subtasks, dispatch those subtasks across the same functional fleet to run **in parallel** — codex on one module, gemini on another, Claude on a third — instead of Claude doing them serially. Rules that carry over: only ✅-functional members (reality-gated); match subtask to the model's strength (see role map); each subtask must be genuinely independent (no shared-file races); respect codex's 5h window. This is execution, not consensus — no reconciliation step, just a join + integrate.

## Enabling blocked members (login, never API keys, never install)

- **cursor — context-blocked, not a quick fix.** `agent login` succeeds interactively (`agent status` → logged in), but the automation/Bash shell sees "Not logged in" — the session lives in the app/keychain the tool shell can't reach. Headless `agent -p` therefore needs `CURSOR_API_KEY` (declined). Only path today: run cursor from the user's own interactive terminal, not scripted. Leave it OUT of `council.sh` runs.
- **cortex — license-blocked, permanent.** `cortex exec` is not permitted under the current Snowflake license. Don't retry; don't ask the user to MFA — it won't help.
- **gemini:** on `GEMINI_API_KEY`. Google login (subscription) is preferred — offer to switch; don't rip out the working key without the user's go-ahead. If it 429s, it auto-retries (30s+) — that's the quota, not a hang.
- If a CLI is **not installed**, report it and stop. Never install one to pad the roster.

## Common mistakes

- **Serial when it could be parallel** — always fan out concurrently; a member hang must not block others (the helper backgrounds each).
- **Letting a model see peers' answers** — kills independence. Collect all, THEN reconcile.
- **Looping past codex's window** — default to one round; the weekly cap doesn't reset for days.
- **Trusting exit 0 = good answer** — read stderr; gemini 429 / codex rate-limit / cursor auth surface there.

## Files

- `scripts/probe.sh` — reality check: ⛔ not-installed / ❌ not-functional / ✅ functional per member. Never installs. **Run first.**
- `scripts/preflight.sh` — cheap canary (one tiny prompt/member) with timing + GO/NO-GO. Run before spending real tokens on a heavy review.
- `scripts/council.sh` — concurrent fan-out; `-f FILE` or `-p PROMPT`, optional `--members`. Backgrounds each member (`</dev/null` so none hangs on stdin); writes `council-runs/<ts>/<member>.md`.
