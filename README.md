# ai-review

Reusable GitHub Actions workflow that reviews pull requests with an LLM on
[Ollama Cloud](https://ollama.com) and posts one sticky comment plus a check (`ai-review / review`).

- No third-party actions. Never checks out or runs PR code; reads the PR through the GitHub API.
- Stdlib-only Python (`ai_review.py`), embedded into `.github/workflows/review.yml` by `build.sh`,
  so pinning a commit SHA pins workflow + script + prompt together. `drift-check` fails if they differ.
- Only runs for repositories owned by `jukasdrj` (others get a skipped no-op).

## Use it
Copy `examples/ai-review.yml` to `.github/workflows/ai-review.yml`, replace the SHA with a released
commit, and add the `OLLAMA_API_KEY` Actions secret:

```sh
( . ~/.config/grok-critic/env; printf %s "$OLLAMA_API_KEY" ) | gh secret set OLLAMA_API_KEY -R OWNER/REPO
```

Use `pull_request` only (never `pull_request_target`). Pass the secret explicitly, not `secrets: inherit`.

## Inputs
| input | default | meaning |
|---|---|---|
| `fail_on` | `STOP` | verdicts that fail the check (`STOP` or `STOP,REVISE`) |
| `models` | `glm-5.3,mistral-large-4` | primary,fallback |
| `second_model` | `mistral-large-4` | extra opinion for high-risk paths; `""` = off |
| `think` | `low` | Ollama reasoning effort |
| `max_chars` | `120000` | diff budget (~30k tokens) |
| `fork_policy` | `fail` | fork PRs get no secret, so they cannot be reviewed: `fail` or `pass` |

## Outcomes
| situation | verdict | check |
|---|---|---|
| model says SHIP / REVISE | SHIP / REVISE | pass (REVISE shows a warning) |
| model says STOP | STOP | **fail** |
| Ollama error, bad model, missing key, Dependabot | UNAVAILABLE | pass (fail-open) + Actions warning |
| fork PR | – | **fail** (`fork_policy: fail`) |
| more files than the GitHub files API returns (>3000) | STOP | **fail** |
| draft PR | – | pass immediately; reviewed on `ready_for_review` |
| GitHub API error | – | fail (re-run) |

The review is advisory; the human merger decides. Prompt-injection text in the PR is treated as data
and reported as a finding. Token-shaped secrets are redacted before the diff is sent.

## Local critic: `tools/review.sh`
A Bash script (needs `curl`, `jq`, GNU `sed`) for a skeptical second-model critique of a plan or diff,
outside Actions. Same Ollama Cloud models as the action (`glm-5.3` primary, `deepseek-v4.1-flash:1017`
second / fast).

```sh
export OLLAMA_API_KEY=...            # or put it in $CRITIC_ENV_FILE (default ~/.config/grok-critic/env)
tools/review.sh PLAN.md              # primary critic
git diff origin/main... | tools/review.sh -2 -   # primary + second opinion, both printed
```
Overrides: `CRITIC_PRIMARY` (or `OLLAMA_MODEL`), `CRITIC_SECOND`, `CRITIC_FAST`, `CRITIC_ENV_FILE`; second and
fast default to the same model. `CRITIC_ENV_FILE` is **sourced as shell** only when `OLLAMA_API_KEY` is unset, so
keep it `chmod 600` and owned by you. `-2` exits 0 if at least one critic answered. The key is never echoed
or put on a command line;
token-shaped strings are crudely redacted before sending. It sends the text to Ollama Cloud, so do not
pipe in anything you would not paste there.

## Change the reviewer
Edit `ai_review.py`, run `./build.sh`, commit both files, tag a release, then bump the pinned SHA in callers.
