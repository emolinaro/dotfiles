# Change log

## 2026-07-28 - Add Codex model selection to `aic`

- Added `-m` and `--model` options to select a Codex model for an individual run.
- Added support for `AIC_MODEL` as the default when no model option is supplied.
- Improved argument parsing, usage guidance, examples, and validation errors.
- Passed the selected model to `codex exec` while retaining path exclusions.

Source: `a1f5d0c`.
