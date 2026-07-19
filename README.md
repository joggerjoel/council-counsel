# council-counsel

A **multi-model review council** for [Claude Code](https://claude.com/claude-code): route the same plan, design, diff, or decision to several frontier-model CLIs _independently_, then reconcile their verdicts. A second opinion that isn't from the same brain.

Instead of one model giving one blended opinion, you get independent verdicts from **Claude + codex + gemini** (and optionally cursor / cortex), reconciled into: **consensus** (high-confidence) and the **5–10% residual dissent** — which is where the real risk usually hides.

## Why

One agent covering every angle goes broad, not deep. A council:

- **Independent-first** — no model sees another's answer before forming its own (no anchoring).
- **Reality-gated** — a model participates only if it's _installed → logged in → functionally returns text_. Nothing is ever auto-installed.
- **Budget-aware** — external CLIs have rolling usage windows (codex's ChatGPT 5h/weekly cap is the scarcest). The council defaults to **one fan-out round** and stops at **90–95% agreement**, never forced unanimity.
- **Login auth only** — uses subscription/login sessions, never API keys.

## Install

Drop it in your Claude Code skills directory:

```bash
git clone https://github.com/joggerjoel/council-counsel.git ~/.claude/skills/council
chmod +x ~/.claude/skills/council/scripts/*.sh
```

Then in Claude Code the `council` skill auto-loads; ask for a "council", "counsel", or "second opinion".

## Use

```bash
scripts/probe.sh                       # who's installed / logged in / functional (never installs)
scripts/preflight.sh                   # cheap canary + timing + GO/NO-GO before a real run
scripts/council.sh -f plan.md          # fan the artifact out to functional members, collect verdicts
scripts/council.sh -p 'question…' --members codex,gemini
```

Each member's verdict lands in `council-runs/<timestamp>/<member>.md`. Claude then reconciles.

## Members

| Member | CLI                     | Auth (login, not API key)              |
| ------ | ----------------------- | -------------------------------------- |
| Claude | native                  | session                                |
| codex  | `codex exec`            | ChatGPT login                          |
| gemini | `gemini -p`             | Google login preferred (API key works) |
| cursor | `agent -p --model auto` | `agent login`                          |
| cortex | `cortex exec`           | Snowflake + TOTP                       |

See [`SKILL.md`](./SKILL.md) for the full protocol: convergence rule, role→model assignment, rate-limit budgeting, and fleet execution (parallel decomposition).

## License

MIT — see [LICENSE](./LICENSE).
