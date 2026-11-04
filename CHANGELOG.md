# Changelog

## v1.1.0 — unreleased (pending tag)
- Second reviewer switched from `mistral-large-4` to `deepseek-v4.1-flash:1017` (DeepSeek):
  `models` default is now `glm-5.3,deepseek-v4.1-flash:1017` and `second_model` default is
  `deepseek-v4.1-flash:1017`. Picked by a bake-off: 6/6 planted bugs caught, 0 false flags.
- Callers that do not override `models` / `second_model` pick this up when they re-pin to the
  v1.1.0 commit SHA. Until the tag exists, callers stay on v1.0.0.

## v1.0.0 — 2026-10-31 (`ec8a93d528068dd2fea27b3aa2a1c417806401da`)
- Initial reusable Ollama Cloud PR reviewer (`glm-5.3` primary, `mistral-large-4` fallback and second opinion).
