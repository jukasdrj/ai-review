#!/usr/bin/env bash
# review.sh — skeptical critique of a plan / code-change from a non-Grok model via Ollama Cloud.
#
# Usage:
#   review.sh PLAN.md                 primary critic   (glm-5.3, Z.ai)
#   review.sh PLAN.md MODEL           any Ollama Cloud tag (back-compat positional form)
#   review.sh --both|-2 PLAN.md       primary + second opinion (deepseek-v4.1-flash:1017, DeepSeek) in parallel, both printed
#   review.sh --fast|-f PLAN.md       cheap/fast critic (deepseek-v4.1-flash:1017, DeepSeek)
#   review.sh -m MODEL PLAN.md        explicit model
#   review.sh -v ...                  also print elapsed time + token counts to stderr
#   cat plan.md | review.sh -         read the plan from stdin
#
# Env overrides: CRITIC_PRIMARY, CRITIC_SECOND, CRITIC_FAST, OLLAMA_MODEL (overrides primary), CRITIC_ENV_FILE.
# Key: OLLAMA_API_KEY from the environment, else sourced from $CRITIC_ENV_FILE
#      (default ${XDG_CONFIG_HOME:-~/.config}/grok-critic/env). Never echoed; no values in this file.
set -euo pipefail
for c in curl jq; do command -v $c >/dev/null || { echo "review.sh needs $c" >&2; exit 2; }; done
CRITIC_ENV_FILE=${CRITIC_ENV_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/grok-critic/env}
[[ -z ${OLLAMA_API_KEY:-} && -f $CRITIC_ENV_FILE ]] && . "$CRITIC_ENV_FILE"
: "${OLLAMA_API_KEY:?OLLAMA_API_KEY not set (export it or put it in \$CRITIC_ENV_FILE)}"

PRIMARY=${CRITIC_PRIMARY:-${OLLAMA_MODEL:-glm-5.3}}
SECOND=${CRITIC_SECOND:-deepseek-v4.1-flash:1017}
FAST=${CRITIC_FAST:-deepseek-v4.1-flash:1017}

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }
MODE=one MODEL="" VERBOSE=0
while [[ $# -gt 0 ]]; do
  case $1 in
    -2|--both) MODE=both; shift ;;
    -f|--fast) MODE=fast; shift ;;
    -m|--model) MODEL=${2:?-m needs a model}; shift 2 ;;
    -v|--verbose) VERBOSE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -) break ;;
    -*) echo "unknown flag: $1" >&2; usage >&2; exit 2 ;;
    *) break ;;
  esac
done
PLAN_FILE=${1:-}; [[ -n $PLAN_FILE ]] || { usage >&2; exit 2; }
[[ -z $MODEL && -n ${2:-} ]] && MODEL=$2
[[ $PLAN_FILE == - || -f $PLAN_FILE ]] || { echo "no such file: $PLAN_FILE" >&2; exit 2; }
[[ $MODE == both && -n $MODEL ]] && { echo "-m/MODEL cannot be combined with -2; use CRITIC_PRIMARY/CRITIC_SECOND" >&2; exit 2; }

SYS='You are a skeptical senior reviewer of a plan written by another AI. Do not praise.
Start with VERDICT: SHIP | REVISE | STOP. Then numbered issues ordered by severity:
wrong or unverified assumptions, missing steps and failure modes, irreversible or risky actions
without an approval gate, and simpler alternatives. Give each a concrete fix. Say "unverifiable"
when you cannot check a claim. Be concise.'
# crude secret scrub before sending (GNU sed). The plan goes to a 0600 temp file, never argv (ARG_MAX, ps).
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
cat -- "$PLAN_FILE" | sed -E 's/(key|token|secret|password)([^A-Za-z0-9]{1,4})[A-Za-z0-9_.\/+=-]{16,}/\1\2<REDACTED>/Ig' >"$work/plan"
grep -q '[^[:space:]]' "$work/plan" || { echo "empty input: nothing to review" >&2; exit 2; }

review() {  # review MODEL -> prints review to stdout, returns non-zero on failure
  local model=$1 resp out i t0
  for i in 1 2 3; do
    t0=$(date +%s)
    resp=$(jq -n --arg s "$SYS" --rawfile p "$work/plan" --arg m "$model" \
      '{model:$m,stream:false,messages:[{role:"system",content:$s},{role:"user",content:$p}]}' |
      curl -sf --max-time 300 https://ollama.com/api/chat -H @<(printf 'Authorization: Bearer %s\n' "$OLLAMA_API_KEY") -d @-) &&
    out=$(jq -r '.message.content // empty' <<<"$resp") && [[ -n $out ]] && {
      echo "## Review by $model"; echo "$out"
      (( VERBOSE )) && jq -r --arg m "$model" --arg t "$(( $(date +%s) - t0 ))" \
        '"[\($m)] \($t)s, prompt \(.prompt_eval_count // "?") tok, output \(.eval_count // "?") tok"' <<<"$resp" >&2
      return 0; }
    echo "[$model] attempt $i failed" >&2
    (( i < 3 )) && sleep $((i*5))
  done
  echo "review failed for model $model" >&2; return 1
}

case $MODE in
  fast) review "${MODEL:-$FAST}" ;;
  one)  review "${MODEL:-$PRIMARY}" ;;
  both)
    tmp=$work
    review "$PRIMARY" >"$tmp/a" & pa=$!
    review "$SECOND"  >"$tmp/b" & pb=$!
    ra=0 rb=0; wait $pa || ra=$?; wait $pb || rb=$?
    cat "$tmp/a"; echo; echo "---"; echo; cat "$tmp/b"
    (( ra == 0 || rb == 0 )) || exit 1   # succeed if at least one critic answered
    ;;
esac
