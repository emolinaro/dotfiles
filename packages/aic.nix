{
  writeShellApplication,
  coreutils,
  git,
  jq,
}:
writeShellApplication {
  name = "aic";
  runtimeInputs = [
    coreutils
    git
    jq
  ];
  text = ''
        excludes=()
        agent="''${AIC_AGENT:-codex}"
        model="''${AIC_MODEL:-}"

        while (( $# > 0 )); do
          case "$1" in
            -h | --help)
              cat <<'EOF'
    Usage: aic [options]
           aic -h | --help

    Stage all changes, generate a commit message with an AI agent, then
    open the Git editor to review and commit.

    Options:
      -a, --agent NAME    Agent that writes the message: codex (default)
                          or opencode (overrides AIC_AGENT)
      -m, --model NAME    Model for this run (overrides AIC_MODEL).
                          opencode default: opencode/nemotron-3-ultra-free
      --exclude path ...  Stage everything, then unstage these paths
      -h, --help          Show this help

    Environment:
      AIC_AGENT           Default agent when -a/--agent is omitted
      AIC_MODEL           Default model when -m/--model is omitted

    Examples:
      aic
      aic --agent opencode
      aic --agent opencode -m opencode/nemotron-3-ultra-free
      aic --exclude README.md
      aic -m gpt-5.6-luna
      AIC_AGENT=opencode aic --exclude secrets.env
    EOF
        exit 0
              ;;
            -a | --agent)
              if [[ -z "''${2:-}" ]]; then
                printf '%s\n' "aic: $1 requires an agent name" >&2
                exit 1
              fi
              agent="$2"
              shift 2
              ;;
            -m | --model)
              if [[ -z "''${2:-}" ]]; then
                printf '%s\n' "aic: $1 requires a model name" >&2
                exit 1
              fi
              model="$2"
              shift 2
              ;;
            --exclude)
              shift
              if (( $# == 0 )); then
                printf '%s\n' "aic: --exclude requires at least one path" >&2
                exit 1
              fi
              excludes=("$@")
              break
              ;;
            *)
              printf '%s\n' "aic: unknown argument: $1" >&2
              printf '%s\n' "Try 'aic --help' for usage." >&2
              exit 1
              ;;
          esac
        done

        case "$agent" in
          codex) ;;
          opencode)
            # Free through OpenCode, convenient for commit messages.
            model="''${model:-opencode/nemotron-3-ultra-free}"
            ;;
          *)
            printf '%s\n' "aic: unknown agent: $agent (want: codex or opencode)" >&2
            exit 1
            ;;
        esac

        git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
          printf '%s\n' "Error: not inside a Git repository" >&2
          exit 1
        }

        # Stage new, modified and deleted files.
        git add -A || exit 1

        if (( ''${#excludes[@]} > 0 )); then
          git restore --staged -- "''${excludes[@]}" || exit 1
        fi

        if git diff --cached --quiet; then
          printf '%s\n' "Nothing to commit"
          exit 0
        fi

        message_requirements='Produce only a Git commit message. Do not include commentary,
    Markdown fences, headings such as "Commit message", or analysis.

    Use this format:

    1. An imperative subject line of at most 72 characters.
    2. A blank line.
    3. Two to six concise bullet points explaining in plain English:
       - what changed;
       - how behaviour or workflow is affected;
       - important implementation or configuration details;
       - why the change matters, but only when evident from the diff.

    Group related changes conceptually instead of merely listing filenames.
    Do not invent motivations or claim that tests passed.
    Do not modify any files.'

        message_file=$(mktemp "''${TMPDIR:-/tmp}/aic-commit.XXXXXX") || {
          printf '%s\n' "Could not create temporary commit-message file" >&2
          exit 1
        }
        event_file=""
        err_file=""
        trap 'rm -f -- "$message_file"; [[ -z "$event_file" ]] || rm -f -- "$event_file"; [[ -z "$err_file" ]] || rm -f -- "$err_file"' EXIT

        rc=0
        if [[ "$agent" == "codex" ]]; then
          codex_args=(
            exec
            --ephemeral
            --sandbox read-only
            --output-last-message "$message_file"
          )
          if [[ -n "$model" ]]; then
            codex_args+=(-m "$model")
          fi

          codex "''${codex_args[@]}" \
            "
    Inspect the staged Git changes by running:

        git diff --cached --stat
        git diff --cached

$message_requirements
    " >/dev/null 2>&1 || rc=$?
          if (( rc != 0 )); then
            exit "$rc"
          fi
        else
          event_file=$(mktemp "''${TMPDIR:-/tmp}/aic-commit-events.XXXXXX") || {
            printf '%s\n' "Could not create temporary event file" >&2
            exit 1
          }

          err_file=$(mktemp "''${TMPDIR:-/tmp}/aic-commit-err.XXXXXX") || {
            printf '%s\n' "Could not create temporary error file" >&2
            exit 1
          }

          opencode_config='{"agent":{"aic":{"description":"Generate Git commit messages from supplied diffs","mode":"primary","permission":{"*":"deny"}}}}'

          # Free models occasionally fail mid-stream, so retry once.
          for attempt in 1 2; do
            rc=0
            {
              printf '%s\n' "Create a Git commit message for the staged changes below.

$message_requirements

    --- git diff --cached --stat ---"
              git diff --cached --stat
              printf '%s\n' "
    --- git diff --cached ---"
              git diff --cached
            } | OPENCODE_CONFIG_CONTENT="$opencode_config" opencode run \
              --pure \
              --agent aic \
              --format json \
              -m "$model" \
              >|"$event_file" 2>|"$err_file" || rc=$?

            session_id=$(
              jq --slurp --raw-output \
                'map(select(.sessionID? != null) | .sessionID) | first // empty' \
                "$event_file" 2>/dev/null
            )
            if [[ -n "$session_id" ]] \
              && ! opencode session delete "$session_id" --pure >/dev/null 2>&1; then
              printf '%s\n' "aic: could not delete opencode session: $session_id" >&2
              exit 1
            fi

            if (( rc == 0 )); then
              jq --exit-status --raw-output --slurp '
                [
                  .[]
                  | select(.type == "text" and .part.time.end? != null)
                  | .part.text
                  | select(length > 0)
                ]
                | select(length > 0)
                | join("\n")
              ' "$event_file" >|"$message_file" || rc=$?
            fi

            if (( rc == 0 )) && [[ -s "$message_file" ]]; then
              break
            fi
            if (( attempt < 2 )); then
              printf '%s\n' "aic: opencode failed (exit $rc), retrying" >&2
              sleep 2
            fi
          done

          if (( rc != 0 )); then
            printf '%s\n' "aic: opencode failed (exit $rc)" >&2
            if [[ -s "$err_file" ]]; then
              cat "$err_file" >&2
            fi
            exit "$rc"
          fi
        fi

        if [[ ! -s "$message_file" ]]; then
          printf '%s\n' "aic: $agent generated an empty commit message" >&2
          exit 1
        fi

        # Open the generated message and staged diff in the Git editor.
        git commit --verbose --edit --file="$message_file" || rc=$?
        exit "$rc"
  '';
}
