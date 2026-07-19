#!/usr/bin/env bash
# Cheap canary before a real council run: confirm each member is INSTALLED, actually
# returns text (not just auth-OK), and how slow it is — so a broken pipeline costs
# ~1 tiny prompt instead of the full review's tokens/time. Never installs anything.
# Auth policy: subscription/login sessions only, NOT API keys.
# Usage: preflight.sh [--members codex,gemini,cursor,cortex]   (default: all present)
set -u
MEMBERS="codex,gemini,cursor,cortex"
[ "${1:-}" = "--members" ] && MEMBERS="$2"
CANARY='In one short sentence, name one risk of retrying a payment API call.'
CODEX="$(command -v codex || echo ~/.local/bin/codex)"; AGENT="$(command -v agent || echo ~/.local/bin/agent)"
CORTEX="$(command -v cortex || echo ~/.local/bin/cortex)"; GEMINI="$(command -v gemini || echo ~/.nvm/versions/node/*/bin/gemini)"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT

run() { # member binary cmd...
  local m="$1" bin="$2"; shift 2
  case ",$MEMBERS," in *,$m,*) ;; *) return;; esac
  if [ ! -x "$bin" ] && ! command -v "$bin" >/dev/null 2>&1; then echo MISSING >"$OUT/$m.state"; return; fi
  echo PRESENT >"$OUT/$m.state"
  ( s=$(date +%s); "$@" </dev/null >"$OUT/$m" 2>"$OUT/$m.e"; rc=$?; e=$(date +%s)
    echo "$rc" >"$OUT/$m.rc"; echo $((e-s)) >"$OUT/$m.t" ) &
}
echo "Preflight canary → members: $MEMBERS  (login auth only, no API keys, no installs)"
run codex  "$CODEX"  "$CODEX"  exec --skip-git-repo-check -c model_reasoning_effort=high "$CANARY"
run gemini "$GEMINI" env GEMINI_CLI_TRUST_WORKSPACE=true "$GEMINI" -p "$CANARY" --model gemini-2.5-flash
run cursor "$AGENT"  "$AGENT"  -p "$CANARY" --output-format text --model auto
run cortex "$CORTEX" "$CORTEX" exec "$CANARY"
wait

printf '\n%-8s %-14s %-4s %-5s  %s\n' MEMBER STATE RC SECS SAMPLE
go=0; slow=0
for m in codex gemini cursor cortex; do
  st="$(cat "$OUT/$m.state" 2>/dev/null || echo "")"
  [ -z "$st" ] && continue
  if [ "$st" = MISSING ]; then printf '%-8s %-14s %-4s %-5s  %s\n' "$m" "⛔ not-installed" "-" "-" "(never auto-install)"; continue; fi
  rc="$(cat "$OUT/$m.rc" 2>/dev/null)"; t="$(cat "$OUT/$m.t" 2>/dev/null)"
  body="$(tr -d '\r' <"$OUT/$m" | grep -v '^\[STARTUP\]' | tr '\n' ' ' | sed 's/  */ /g')"
  if [ "$rc" = 0 ] && [ -n "${body// /}" ]; then state="✅ functional"; go=$((go+1)); [ "${t:-0}" -gt 45 ] && slow=$((slow+1))
  else state="❌ not-func"; body="$(head -1 "$OUT/$m.e" | cut -c1-64)"; fi
  printf '%-8s %-14s %-4s %-5s  %s\n' "$m" "$state" "${rc:-?}" "${t:-?}s" "$(echo "$body" | cut -c1-64)"
done
echo
if [ "$go" -ge 2 ]; then
  echo "GO — $go members functional. Real-run wall-clock ≈ slowest above (parallel)."
  [ "$slow" -gt 0 ] && echo "     ⚠ $slow member(s) >45s — background the real run, poll; never block."
  exit 0
else
  echo "NO-GO — only $go functional. Fix login (probe.sh) before spending real tokens. Do NOT install."
  exit 1
fi
