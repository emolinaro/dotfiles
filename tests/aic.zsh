#!/usr/bin/env zsh

set -euo pipefail

if (( $# != 1 )); then
  print -u2 "Usage: $0 PATH_TO_ZSH_INIT_CONTENT"
  exit 2
fi

readonly init_content_file="$1"
readonly test_root="$(mktemp -d "${TMPDIR:-/tmp}/aic-test.XXXXXX")"
readonly function_file="$test_root/aic-function.zsh"
readonly codex_log="$test_root/codex.log"
readonly opencode_log="$test_root/opencode.log"
readonly opencode_config_log="$test_root/opencode-config.log"
readonly opencode_prompt_log="$test_root/opencode-prompt.log"
readonly opencode_run_count_file="$test_root/opencode-run-count"
readonly repository="$test_root/repository"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

fail() {
  print -u2 "FAIL: $*"
  exit 1
}

assert_contains() {
  local actual="$1"
  local expected="$2"
  local context="$3"
  [[ "$actual" == *"$expected"* ]] \
    || fail "$context: expected to find ${(qqq)expected} in ${(qqq)actual}"
}

assert_not_contains() {
  local actual="$1"
  local unexpected="$2"
  local context="$3"
  [[ "$actual" != *"$unexpected"* ]] \
    || fail "$context: did not expect ${(qqq)unexpected} in ${(qqq)actual}"
}

awk '
  /^[[:space:]]*aic\(\) \{/ { capture = 1 }
  capture && /^alias --/ { exit }
  capture { print }
' "$init_content_file" >|"$function_file"

source "$function_file"
(( $+functions[aic] )) || fail "could not load aic from evaluated Zsh init content"

codex() {
  print -r -- "${(j: :)argv[1,-2]}" >>"$codex_log"

  local message_file=""
  local index=1
  while (( index <= $# )); do
    if [[ "${argv[$index]}" == "--output-last-message" ]]; then
      (( index < $# )) || return 64
      message_file="${argv[$(( index + 1 ))]}"
      break
    fi
    (( index += 1 ))
  done

  [[ -n "$message_file" ]] || return 64
  print -r -- "Codex generated subject

- Preserve the existing Codex commit workflow" >|"$message_file"
}

opencode() {
  print -r -- "${(j: :)argv}" >>"$opencode_log"

  if [[ "$1" == "session" && "${2:-}" == "delete" ]]; then
    [[ "${AIC_TEST_OPENCODE_MODE:-success}" != "delete-fail" ]]
    return
  fi

  [[ "$1" == "run" ]] || return 64
  print -r -- "${OPENCODE_CONFIG_CONTENT:-}" >>"$opencode_config_log"
  cat >>"$opencode_prompt_log"

  local run_count=0
  if [[ -f "$opencode_run_count_file" ]]; then
    run_count="$(<"$opencode_run_count_file")"
  fi
  (( run_count += 1 ))
  print -r -- "$run_count" >|"$opencode_run_count_file"

  local mode="${AIC_TEST_OPENCODE_MODE:-success}"
  local session_id="session-$mode-$run_count"

  if [[ "$mode" == "retry" && "$run_count" == "1" ]]; then
    print -r -- \
      "{\"type\":\"error\",\"sessionID\":\"$session_id\",\"error\":\"transient model failure\"}"
    print -u2 "transient model failure"
    return 42
  fi

  print -r -- \
    "{\"type\":\"step_start\",\"sessionID\":\"$session_id\",\"part\":{\"type\":\"step-start\"}}"
  print -r -- \
    "{\"type\":\"text\",\"sessionID\":\"$session_id\",\"part\":{\"text\":\"OpenCode generated subject\\n\\n- Use the selected OpenCode model\",\"time\":{\"end\":1}}}"
}

sleep() {
  :
}

mkdir -p "$repository" "$test_root/home"
export HOME="$test_root/home"
export GIT_EDITOR=true

git -C "$repository" init --quiet
git -C "$repository" config user.name "AIC Test"
git -C "$repository" config user.email "aic-test@example.invalid"
git -C "$repository" config commit.gpgsign false
print -r -- "initial" >"$repository/tracked.txt"
print -r -- "keep this version" >"$repository/excluded.txt"
git -C "$repository" add tracked.txt excluded.txt
git -C "$repository" commit --quiet -m "Initial commit"
cd "$repository"

print '$ aic --help'
help_output="$(aic --help)"
print -r -- "$help_output"
assert_contains "$help_output" "--agent NAME" "help"
assert_contains "$help_output" "opencode/nemotron-3-ultra-free" "help"

print -r -- "codex default change" >>tracked.txt
print '$ aic'
codex_output="$(aic)"
print -r -- "$codex_output"
codex_message="$(git log -1 --pretty=%B)"
print 'Created commit message:'
print -r -- "$codex_message"
codex_invocation="$(<"$codex_log")"
print "Codex invocation: $codex_invocation"
[[ "$codex_message" == $'Codex generated subject\n\n- Preserve the existing Codex commit workflow' ]] \
  || fail "default Codex commit message was not used"
assert_contains "$codex_invocation" "exec --ephemeral --sandbox read-only --output-last-message" \
  "default Codex invocation"
assert_not_contains "$codex_invocation" " -m " "default Codex invocation"

print -r -- "codex custom model change" >>tracked.txt
print '$ aic --model codex/custom-model'
codex_model_output="$(aic --model codex/custom-model)"
print -r -- "$codex_model_output"
codex_model_invocation="$(tail -n 1 "$codex_log")"
print "Codex invocation: $codex_model_invocation"
assert_contains "$codex_model_invocation" "-m codex/custom-model" "Codex model override"

print -r -- "included change" >>tracked.txt
print -r -- "excluded change" >>excluded.txt
print '$ aic --exclude excluded.txt'
exclude_output="$(aic --exclude excluded.txt)"
print -r -- "$exclude_output"
committed_names="$(git show --format= --name-only HEAD)"
unstaged_names="$(git diff --name-only)"
print "Committed paths: ${(j:, :)${(f)committed_names}}"
print "Still unstaged: ${(j:, :)${(f)unstaged_names}}"
assert_contains "$committed_names" "tracked.txt" "exclude behavior"
assert_not_contains "$committed_names" "excluded.txt" "exclude behavior"
assert_contains "$unstaged_names" "excluded.txt" "exclude behavior"
git restore -- excluded.txt

print -r -- "opencode default model change" >>tracked.txt
: >|"$opencode_log"
: >|"$opencode_config_log"
: >|"$opencode_prompt_log"
rm -f "$opencode_run_count_file"
unset AIC_TEST_OPENCODE_MODE
print '$ aic --agent opencode'
opencode_output="$(aic --agent opencode)"
print -r -- "$opencode_output"
opencode_message="$(git log -1 --pretty=%B)"
opencode_invocation="$(head -n 1 "$opencode_log")"
opencode_session_delete="$(tail -n 1 "$opencode_log")"
opencode_config="$(<"$opencode_config_log")"
opencode_prompt="$(<"$opencode_prompt_log")"
print 'Created commit message:'
print -r -- "$opencode_message"
print "OpenCode invocation: $opencode_invocation"
print "Session cleanup: $opencode_session_delete"
[[ "$opencode_message" == $'OpenCode generated subject\n\n- Use the selected OpenCode model' ]] \
  || fail "OpenCode commit message was not extracted from JSON events"
assert_contains "$opencode_invocation" \
  "run --pure --agent aic --format json -m opencode/nemotron-3-ultra-free" \
  "default OpenCode invocation"
assert_contains "$opencode_session_delete" \
  "session delete session-success-1 --pure" \
  "OpenCode session cleanup"
assert_contains "$opencode_config" '"permission":{"*":"deny"}' "OpenCode inline configuration"
assert_contains "$opencode_prompt" "opencode default model change" "OpenCode staged diff prompt"
assert_contains "$opencode_prompt" "Produce only a Git commit message" "OpenCode message requirements"

print -r -- "opencode custom model change" >>tracked.txt
: >|"$opencode_log"
rm -f "$opencode_run_count_file"
print '$ AIC_AGENT=opencode AIC_MODEL=provider/custom-model aic'
opencode_model_output="$(
  AIC_AGENT=opencode AIC_MODEL=provider/custom-model aic
)"
print -r -- "$opencode_model_output"
opencode_model_invocation="$(head -n 1 "$opencode_log")"
print "OpenCode invocation: $opencode_model_invocation"
assert_contains "$opencode_model_invocation" \
  "run --pure --agent aic --format json -m provider/custom-model" \
  "OpenCode environment selection and model override"

print -r -- "opencode retry change" >>tracked.txt
: >|"$opencode_log"
rm -f "$opencode_run_count_file"
export AIC_TEST_OPENCODE_MODE=retry
print '$ aic --agent opencode  # first model call fails, second succeeds'
if retry_output="$(aic --agent opencode 2>&1)"; then
  :
else
  fail "aic did not recover from the first OpenCode failure"
fi
print -r -- "$retry_output"
retry_run_count="$(awk '/^run / { count++ } END { print count + 0 }' "$opencode_log")"
retry_delete_count="$(awk '/^session delete / { count++ } END { print count + 0 }' "$opencode_log")"
print "OpenCode run attempts: $retry_run_count"
print "Sessions deleted: $retry_delete_count"
[[ "$retry_run_count" == "2" ]] || fail "OpenCode was not attempted twice"
[[ "$retry_delete_count" == "2" ]] || fail "both OpenCode retry sessions were not deleted"
assert_contains "$retry_output" "opencode failed (exit 42), retrying" "OpenCode retry output"

print -r -- "session cleanup failure change" >>tracked.txt
: >|"$opencode_log"
rm -f "$opencode_run_count_file"
export AIC_TEST_OPENCODE_MODE=delete-fail
head_before_cleanup_failure="$(git rev-parse HEAD)"
print '$ aic --agent opencode  # session deletion fails'
if cleanup_failure_output="$(aic --agent opencode 2>&1)"; then
  fail "aic succeeded even though OpenCode session deletion failed"
fi
print -r -- "$cleanup_failure_output"
head_after_cleanup_failure="$(git rev-parse HEAD)"
[[ "$head_before_cleanup_failure" == "$head_after_cleanup_failure" ]] \
  || fail "aic committed after OpenCode session deletion failed"
assert_contains "$cleanup_failure_output" \
  "could not delete opencode session: session-delete-fail-1" \
  "OpenCode session deletion failure"

unset AIC_TEST_OPENCODE_MODE
print 'All focused aic scenarios completed successfully.'
