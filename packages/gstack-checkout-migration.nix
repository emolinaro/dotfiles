{
  coreutils,
  writeShellApplication,
}:

writeShellApplication {
  name = "migrate-gstack-checkout";
  runtimeInputs = [ coreutils ];
  text = ''
    set -euo pipefail

    if [[ "$#" -ne 1 ]]; then
      echo "usage: migrate-gstack-checkout TARGET_CHECKOUT" >&2
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

    if ! path_exists "$legacy_repositories"; then
      exit 0
    fi

    if ! path_exists "$target_checkout" && path_exists "$legacy_checkout"; then
      mkdir -p "$(dirname "$target_checkout")"
      mv "$legacy_checkout" "$target_checkout"
    fi

    if rmdir "$legacy_repositories" 2>/dev/null; then
      exit 0
    fi

    archive_root="$HOME/.local/share/gstack"
    archive="$archive_root/legacy-repos"
    suffix=0
    while path_exists "$archive"; do
      suffix=$((suffix + 1))
      archive="$archive_root/legacy-repos-$suffix"
    done

    mkdir -p "$archive_root"
    mv "$legacy_repositories" "$archive"
    echo "Moved deprecated gstack repositories to $archive" >&2
  '';
}
