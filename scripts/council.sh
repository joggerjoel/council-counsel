#!/usr/bin/env bash
# Fan a single prompt out to the authenticated council CLIs, concurrently.
# Usage:
#   council.sh -p 'PROMPT'                  # inline prompt
#   council.sh -f path/to/artifact.md       # prompt = review instructions + file contents
#   council.sh -f FILE --members codex,gemini
# Writes each verdict to ./council-runs/<UTC-timestamp>/<member>.md and prints the dir.
# Unauthenticated members are skipped with a note (never blocks the run).
set -u

PROMPT=""; FILE=""; MEMBERS="claude,codex,gemini"
while [ $# -gt 0 ]; do case "$1" in
  -p) PROMPT="$2"; shift 2;;
  -f) FILE="$2"; shift 2;;
  --members) MEMBERS="$2"; shift 2;;
  *) echo "unknown arg: $1" >&2; exit 2;;
esac; done

if [ -n "$FILE" ]; then
  [ -r "$FILE" ] || { echo "cannot read $FILE" >&2; exit 1; }
  PROMPT="You are one member of an independent review council. Review the artifact below.
List the top risks, wrong assumptions, missing cases, and anything you'd change. Be specific and cite lines/sections. Do not hedge; a sharp dissent is more useful than agreement.

--- ARTIFACT: $FILE ---
$(cat "$FILE")"
fi
[ -n "$PROMPT" ] || { echo "need -p PROMPT or -f FILE" >&2; exit 2; }

OUT="council-runs/$(date -u +%Y%m%dT%H%M%SZ)"; mkdir -p "$OUT"
CLAUDE="$(command -v claude || echo ~/.local/bin/claude)"
CODEX="$(command -v codex || echo ~/.local/bin/codex)"
AGENT="$(command -v agent || echo ~/.local/bin/agent)"
CORTEX="$(command -v cortex || echo ~/.local/bin/cortex)"
GEMINI="$(command -v gemini || echo ~/.nvm/versions/node/*/bin/gemini)"
: "${MEMBER_TIMEOUT:=240}"   # per-member hard cap (s); override via env for big artifacts
run() { # member cmd...
  local m="$1"; shift
  # </dev/null is REQUIRED: codex/gemini/agent read stdin when it's a pipe and block
  # waiting for EOF. perl alarm bounds each member so a gemini 429-retry storm or a
  # cursor auth stall can't hang the whole fan-out.
  ( perl -e 'alarm shift; exec @ARGV' "$MEMBER_TIMEOUT" "$@" </dev/null >"$OUT/$m.md" 2>"$OUT/$m.err"
    echo -e "\n\n<!-- rc=$? -->" >>"$OUT/$m.md" ) &
  echo "  → $m dispatched (≤${MEMBER_TIMEOUT}s)"
}

echo "Council fan-out → $OUT"
case ",$MEMBERS," in *,claude,*) run claude "$CLAUDE" -p "$PROMPT" --model opus;; esac
case ",$MEMBERS," in *,codex,*)  run codex  "$CODEX" exec --skip-git-repo-check -c model_reasoning_effort=high "$PROMPT";; esac
case ",$MEMBERS," in *,gemini,*) run gemini env GEMINI_CLI_TRUST_WORKSPACE=true "$GEMINI" -p "$PROMPT" --model gemini-2.5-flash;; esac
case ",$MEMBERS," in *,cursor,*) run cursor "$AGENT" -p "$PROMPT" --output-format text --model auto;; esac
case ",$MEMBERS," in *,cortex,*) run cortex "$CORTEX" exec "$PROMPT";; esac
wait

echo "Done. Verdicts:"
for f in "$OUT"/*.md; do echo "  $f ($(wc -l <"$f" | tr -d ' ') lines)"; done
echo "$OUT"
