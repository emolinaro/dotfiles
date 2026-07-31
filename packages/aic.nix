{
  writeShellApplication,
  coreutils,
  git,
}:
writeShellApplication {
  name = "aic";
  runtimeInputs = [
    coreutils
    git
  ];
  text = ''
        excludes=()
        model="''${AIC_MODEL:-}"

        while (( $# > 0 )); do
          case "$1" in
            -h | --help)
              cat <<'EOF'
    Usage: aic [options]
           aic -h | --help

    Stage all changes, generate a commit message with Codex, then open
    the Git editor to review and commit.

    Options:
      -m, --model NAME    Codex model for this run (overrides AIC_MODEL)
      --exclude path ...  Stage everything, then unstage these paths
      -h, --help          Show this help

    Environment:
      AIC_MODEL           Default Codex model when -m/--model is omitted

    Examples:
      aic
      aic --exclude README.md
      aic -m gpt-5.6-luna
      AIC_MODEL=gpt-5.6-luna aic --exclude secrets.env
    EOF
        exit 0
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

        message_file=$(mktemp "''${TMPDIR:-/tmp}/codex-commit.XXXXXX") || {
          printf '%s\n' "Could not create temporary commit-message file" >&2
          exit 1
        }

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
          '
    Inspect the staged Git changes by running:

        git diff --cached --stat
        git diff --cached

    Produce only a Git commit message. Do not include commentary,
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
    Do not modify any files.
    ' >/dev/null 2>&1 || {
          status=$?
          rm -f "$message_file"
          exit "$status"
        }

        if [[ ! -s "$message_file" ]]; then
          printf '%s\n' "Codex generated an empty commit message" >&2
          rm -f "$message_file"
          exit 1
        fi

        # Open the generated message and staged diff in the Git editor.
        git commit --verbose --edit --file="$message_file"
        status=$?

        rm -f "$message_file"
        exit "$status"
  '';
}
