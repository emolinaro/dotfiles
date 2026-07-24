{
  coreutils,
  writeShellApplication,
}:

writeShellApplication {
  name = "migrate-gstack-checkout";
  runtimeInputs = [ coreutils ];
  text = ''
    set -euo pipefail

    dry_run=0
    if [[ "''${1:-}" == "--dry-run" ]]; then
      dry_run=1
      shift
    fi
    if [[ "$#" -ne 1 ]]; then
      echo "usage: migrate-gstack-checkout [--dry-run] TARGET_CHECKOUT" >&2
      exit 64
    fi

    target_checkout=$1
    legacy_repositories="$HOME/.gstack/repos"
    legacy_checkout="$legacy_repositories/gstack"

    case "$target_checkout" in
      "$HOME"/*) ;;
      *)
        echo "error: target checkout must be inside HOME" >&2
        exit 64
        ;;
    esac

    case "$target_checkout" in
      "$HOME/.gstack" | "$HOME/.gstack"/*)
        echo "error: target checkout must be outside gstack state" >&2
        exit 64
        ;;
    esac

    path_exists() {
      [[ -e "$1" || -L "$1" ]]
    }

    if ! path_exists "$legacy_checkout" || path_exists "$target_checkout"; then
      exit 0
    fi

    if [[ "$dry_run" -eq 1 ]]; then
      echo "Would move $legacy_checkout to $target_checkout" >&2
      exit 0
    fi

    mkdir -p "$(dirname "$target_checkout")"
    mv "$legacy_checkout" "$target_checkout"
    rmdir "$legacy_repositories" 2>/dev/null || true
    echo "Moved deprecated gstack checkout to $target_checkout" >&2
  '';
}
