#!/usr/bin/env bash
# Reality check for the council roster. Reports THREE states per member, never installs:
#   ⛔ not installed   ·   ❌ installed but not authed/functional   ·   ✅ functional
# Auth policy: subscription/login sessions (ChatGPT, `agent login`, Google login) — NOT API keys.
set -u
CODEX="$(command -v codex  || echo ~/.local/bin/codex)"
AGENT="$(command -v agent  || echo ~/.local/bin/agent)"
CORTEX="$(command -v cortex || echo ~/.local/bin/cortex)"
GEMINI="$(command -v gemini || echo ~/.nvm/versions/node/*/bin/gemini)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# name binary cmd... : only runs if binary exists; records installed/rc/output
probe() {
  local m="$1" bin="$2"; shift 2
  if [ ! -x "$bin" ] && ! command -v "$bin" >/dev/null 2>&1; then echo "MISSING" >"$TMP/$m.state"; return; fi
  echo "PRESENT" >"$TMP/$m.state"
  # perl alarm bounds each member: a rate-limited/hanging CLI (gemini 429 retries,
  # cursor headless-auth stall) can't hold up the whole probe. 60s is plenty for a canary.
  ( perl -e 'alarm 60; exec @ARGV' "$@" </dev/null >"$TMP/$m" 2>&1; echo "rc=$?" >>"$TMP/$m" ) &
}
probe codex  "$CODEX"  "$CODEX"  exec --skip-git-repo-check 'reply with exactly: OK'
probe cursor "$AGENT"  "$AGENT"  -p 'reply with exactly: OK' --output-format text --model auto
probe cortex "$CORTEX" "$CORTEX" exec 'reply with exactly: OK'
probe gemini "$GEMINI" env GEMINI_CLI_TRUST_WORKSPACE=true "$GEMINI" -p 'reply with exactly: OK' --model gemini-2.5-flash
wait

for m in codex gemini cursor cortex; do
  st="$(cat "$TMP/$m.state" 2>/dev/null || echo MISSING)"
  if [ "$st" = MISSING ]; then echo "⛔ $m: not installed (do NOT install unless the user asks)"
  elif grep -q '^OK' "$TMP/$m" 2>/dev/null; then echo "✅ $m: functional ($(grep -o 'rc=[0-9]*' "$TMP/$m" | tail -1))"
  else echo "❌ $m: installed, not functional — $(grep -iE 'auth|login|MFA|TOTP|api.key|error|quota|429|trust' "$TMP/$m" | head -1 | cut -c1-80)"; fi
done
