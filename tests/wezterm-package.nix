{
  pkgs,
  weztermPackage,
}:

pkgs.runCommand "wezterm-package-test" { nativeBuildInputs = [ weztermPackage ]; } ''
  set -euo pipefail

  test "$(wezterm --version)" = "wezterm ${weztermPackage.version}"

  # The GUI needs the Mesa pointers at runtime; keep both entry points wrapped.
  for program in wezterm wezterm-gui; do
    wrapper="${weztermPackage}/bin/$program"
    test -x "$wrapper"
    grep -q 'LIBGL_DRIVERS_PATH' "$wrapper"
    grep -q '__EGL_VENDOR_LIBRARY_FILENAMES' "$wrapper"
  done

  touch "$out"
''
