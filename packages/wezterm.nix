{
  lib,
  libglvnd,
  makeWrapper,
  mesa,
  symlinkJoin,
  wezterm,
}:

# WezTerm on non-NixOS distros must not use the system OpenGL stack: the Nix
# binary runs against nixpkgs glibc, and mixing in distro libraries (Arch's
# libEGL, Ubuntu's multiarch libs) crashes the process. Give it a self-contained
# nixpkgs Mesa stack instead, mirroring what nixGL does. The nixpkgs libglvnd
# ships no EGL vendor configuration, so point it straight at Mesa's vendor JSON
# and DRI drivers; those talk to the kernel like the distro's Mesa does.
symlinkJoin {
  name = "wezterm-${wezterm.version}";
  inherit (wezterm) version;

  paths = [ wezterm ];

  nativeBuildInputs = [ makeWrapper ];

  postBuild = ''
    for program in wezterm wezterm-gui; do
      wrapProgram "$out/bin/$program" \
        --prefix LD_LIBRARY_PATH : "${
          lib.makeLibraryPath [
            mesa
            libglvnd
          ]
        }" \
        --set GBM_BACKENDS_PATH "${mesa}/lib/gbm" \
        --set LIBGL_DRIVERS_PATH "${mesa}/lib/dri" \
        --set __EGL_VENDOR_LIBRARY_FILENAMES "${mesa}/share/glvnd/egl_vendor.d/50_mesa.json"
    done
  '';

  meta = wezterm.meta // {
    description = "${wezterm.meta.description} (wrapped for the nixpkgs Mesa stack)";
  };
}
