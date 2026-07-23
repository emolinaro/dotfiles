{
  migrationPackage,
  pkgs,
}:

pkgs.runCommand "gstack-checkout-migration-test" { } ''
  set -euo pipefail

  export HOME="$TMPDIR/home-dry-run"
  target="$HOME/.local/share/gstack/repos/gstack"
  mkdir -p \
    "$HOME/.gstack/repos/gstack/.git" \
    "$HOME/.gstack/repos/other/.git"
  printf '%s\n' legacy-gstack > "$HOME/.gstack/repos/gstack/sentinel"
  printf '%s\n' unrelated-repository > "$HOME/.gstack/repos/other/sentinel"

  ${migrationPackage}/bin/migrate-gstack-checkout --dry-run "$target" \
    > "$TMPDIR/dry-run.stdout" 2> "$TMPDIR/dry-run.stderr"

  test -e "$HOME/.gstack/repos/gstack/sentinel"
  test -e "$HOME/.gstack/repos/other/sentinel"
  test ! -e "$target"
  grep -F "Would move $HOME/.gstack/repos/gstack to $target" "$TMPDIR/dry-run.stderr"

  export HOME="$TMPDIR/home-one"
  target="$HOME/.local/share/gstack/repos/gstack"
  mkdir -p \
    "$HOME/.gstack/repos/gstack/.git" \
    "$HOME/.gstack/repos/other/.git"
  printf '%s\n' legacy-gstack > "$HOME/.gstack/repos/gstack/sentinel"
  printf '%s\n' unrelated-repository > "$HOME/.gstack/repos/other/sentinel"

  ${migrationPackage}/bin/migrate-gstack-checkout "$target"

  test -d "$HOME/.gstack/repos"
  test "$(<"$target/sentinel")" = legacy-gstack
  test "$(<"$HOME/.gstack/repos/other/sentinel")" = unrelated-repository

  ${migrationPackage}/bin/migrate-gstack-checkout "$target"
  test "$(<"$HOME/.gstack/repos/other/sentinel")" = unrelated-repository
  test "$(<"$target/sentinel")" = legacy-gstack

  export HOME="$TMPDIR/home-two"
  target="$HOME/.local/share/gstack/repos/gstack"
  mkdir -p \
    "$target/.git" \
    "$HOME/.gstack/repos/gstack/.git" \
    "$HOME/.local/share/gstack/legacy-repos"
  printf '%s\n' active-gstack > "$target/sentinel"
  printf '%s\n' legacy-gstack > "$HOME/.gstack/repos/gstack/sentinel"
  printf '%s\n' existing-archive > "$HOME/.local/share/gstack/legacy-repos/sentinel"

  ${migrationPackage}/bin/migrate-gstack-checkout "$target"

  test "$(<"$target/sentinel")" = active-gstack
  test "$(<"$HOME/.local/share/gstack/legacy-repos/sentinel")" = existing-archive
  test "$(<"$HOME/.gstack/repos/gstack/sentinel")" = legacy-gstack

  touch "$out"
''
