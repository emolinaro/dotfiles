{
  description = "dotfiles";

  inputs = {
    # Keep the core Nix modules on matching release branches.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nixpkgs-linux.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Agent CLIs move quickly, so keep them on a separately pinned unstable input.
    nixpkgs-agents.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # Use Herdr independently so Linux gets the upstream-supported Nix build.
    herdr.url = "github:ogulcancelik/herdr";
    herdr.inputs.nixpkgs.follows = "nixpkgs-linux";

    # Lock agent workflows so rebuilds do not silently pull new behavior.
    gstack = {
      url = "github:garrytan/gstack";
      flake = false;
    };
    superpowers = {
      url = "github:obra/superpowers";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nix-darwin,
      nix-homebrew,
      home-manager,
      nixpkgs,
      nixpkgs-agents,
      nixpkgs-linux,
      herdr,
      gstack,
      superpowers,
    }:
    let
      agentRegistry = import ./runtime/nono-agents.nix;
      envOr =
        name: fallback:
        let
          value = builtins.getEnv name;
        in
        if value == "" then fallback else value;
      sudoUser = builtins.getEnv "SUDO_USER";
      currentUser = builtins.getEnv "USER";
      darwinUsername =
        if sudoUser != "" && sudoUser != "root" then
          sudoUser
        else if currentUser != "" && currentUser != "root" then
          currentUser
        else
          throw "Unable to determine the non-root macOS user. Run the setup as a sudo-capable user with --impure.";
      darwinHomeDirectory = "/Users/${darwinUsername}";
      linuxUsername = envOr "DOTFILES_USERNAME" "ubuntu";
      linuxHomeDirectory = envOr "DOTFILES_HOME" "/home/${linuxUsername}";
      supportedSystems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor =
        system:
        import (if nixpkgs.lib.hasSuffix "-darwin" system then nixpkgs else nixpkgs-linux) {
          inherit system;
          config.allowUnfree = true;
        };
      agentPkgsFor =
        system:
        import nixpkgs-agents {
          inherit system;
          config.allowUnfree = true;
        };
      nonoPackageFor = system: (pkgsFor system).callPackage ./packages/nono.nix { };
      # WezTerm needs the nixpkgs Mesa stack on non-NixOS Linux distros; see
      # packages/wezterm.nix. macOS keeps the Homebrew cask.
      weztermPackageFor =
        system:
        if (pkgsFor system).stdenv.hostPlatform.isLinux then
          (pkgsFor system).callPackage ./packages/wezterm.nix { }
        else
          null;
      # The Axi CLIs and gnhf are packaged from their published npm artifacts
      # (see packages/npm-tool.nix), so one definition serves every system and
      # no source build or pnpm dependency hash is involved.
      axiToolsPackageFor =
        system:
        let
          pkgs = pkgsFor system;
        in
        pkgs.symlinkJoin {
          name = "axi-tools";
          paths = [
            (pkgs.callPackage ./packages/chrome-devtools-axi.nix { })
            (pkgs.callPackage ./packages/gh-axi.nix { })
            (pkgs.callPackage ./packages/lavish-axi.nix { })
            (pkgs.callPackage ./packages/quota-axi.nix { })
            (pkgs.callPackage ./packages/tasks-axi.nix { })
          ];
        };

      gnhfPackageFor = system: (pkgsFor system).callPackage ./packages/gnhf.nix { };
      nonoRuntimeTestFor =
        system:
        (pkgsFor system).callPackage ./tests/nono-runtime.nix {
          inherit agentRegistry;
          nonoPackage = nonoPackageFor system;
          profiles = ./home/.config/nono/profiles;
          wrapperModule = ./runtime/nono-agent-wrappers.nix;
        };

      checksForSystem =
        system:
        let
          pkgs = pkgsFor system;
          lintSrc =
            let
              fs = pkgs.lib.fileset;
            in
            fs.toSource {
              root = ./.;
              fileset = fs.unions [
                (fs.fileFilter (file: file.hasExt "nix") ./.)
                (fs.fileFilter (file: file.hasExt "sh") ./.)
              ];
            };
          linuxPlatformDetectionSrc = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [
              ./scripts/lib-detect.sh
              ./tests/fixtures/os-release
              ./tests/linux-platform-detection.sh
            ];
          };
        in
        {
          format =
            pkgs.runCommand "format-check"
              {
                nativeBuildInputs = [
                  pkgs.nixfmt
                  pkgs.shfmt
                ];
              }
              ''
                cd ${lintSrc}
                find . -name '*.nix' -print0 | xargs -0 nixfmt --check
                find . -name '*.sh' -print0 | xargs -0 shfmt -i 2 -ci -d
                touch "$out"
              '';
          shell-lint = pkgs.runCommand "shell-lint-check" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
            cd ${lintSrc}
            find . -name '*.sh' -print0 | xargs -0 shellcheck -x
            touch "$out"
          '';
          linux-platform-detection =
            pkgs.runCommand "linux-platform-detection-test" { nativeBuildInputs = [ pkgs.bash ]; }
              ''
                cd ${linuxPlatformDetectionSrc}
                bash tests/linux-platform-detection.sh
                touch "$out"
              '';
          axi-tools = pkgs.callPackage ./tests/axi-tools.nix {
            axiToolsPackage = axiToolsPackageFor system;
          };
          gnhf-package = pkgs.callPackage ./tests/gnhf-package.nix {
            gnhfPackage = gnhfPackageFor system;
          };
          gstack-checkout-migration = pkgs.callPackage ./tests/gstack-checkout-migration.nix {
            migrationPackage = pkgs.callPackage ./runtime/gstack-checkout-migration.nix { };
          };
          nono-package = pkgs.callPackage ./tests/nono-package.nix {
            nonoPackage = nonoPackageFor system;
          };
          wezterm-package =
            if pkgs.stdenv.hostPlatform.isLinux then
              pkgs.callPackage ./tests/wezterm-package.nix {
                weztermPackage = weztermPackageFor system;
              }
            else
              pkgs.runCommand "wezterm-package-not-linux" { } ''
                touch "$out"
              '';
          nono-agent-wrappers = pkgs.callPackage ./tests/nono-agent-wrappers.nix {
            inherit agentRegistry;
            profiles = ./home/.config/nono/profiles;
            wrapperModule = ./runtime/nono-agent-wrappers.nix;
          };
          nono-home-command-surface =
            if pkgs.stdenv.hostPlatform.isLinux then
              pkgs.callPackage ./tests/nono-home-command-surface.nix {
                inherit agentRegistry;
                homePath = (mkLinuxHome system).config.home.path;
              }
            else
              pkgs.runCommand "nono-home-command-surface-not-linux" { } ''
                touch "$out"
              '';
          nono-profiles = pkgs.callPackage ./tests/nono-profiles.nix {
            inherit agentRegistry;
            nonoPackage = nonoPackageFor system;
            profiles = ./home/.config/nono/profiles;
          };
          nono-runtime-test = nonoRuntimeTestFor system;
        };

      # One-command validation entry point: `nix build .#ci` builds every
      # check without duplicating their names at the call site.
      ciFor =
        system:
        let
          pkgs = pkgsFor system;
        in
        # linkFarmFromDrvs links the derivations themselves rather than
        # merging their stores, so file-output checks do not collide.
        pkgs.linkFarmFromDrvs "ci" (pkgs.lib.attrValues (checksForSystem system));

      # Shared Home Manager special arguments for both platforms; call sites
      # pass only their per-platform deltas.
      homeSpecialArgsFor =
        system:
        {
          username,
          homeDirectory,
          herdrPackage,
        }:
        let
          axiTools = axiToolsPackageFor system;
        in
        {
          inherit username homeDirectory herdrPackage;
          agentPkgs = agentPkgsFor system;
          axiToolsPackage = axiTools;
          gnhfPackage = gnhfPackageFor system;
          nonoPackage = nonoPackageFor system;
          weztermPackage = weztermPackageFor system;
          # Skills ship inside the npm artifacts, so they cannot drift from the
          # installed CLI.
          chromeDevtoolsAxiSkill = "${axiTools}/lib/node_modules/chrome-devtools-axi/skills/chrome-devtools-axi";
          ghAxiSkill = "${axiTools}/lib/node_modules/gh-axi/skills/gh-axi";
          lavishSkill = "${axiTools}/lib/node_modules/lavish-axi/skills/lavish";
          quotaAxiSkill = "${axiTools}/lib/node_modules/quota-axi/skills/quota-axi";
          superpowersSkill = "${superpowers}/skills";
          tasksAxiSkill = "${axiTools}/lib/node_modules/tasks-axi/skills/tasks-axi";
          gstackRev = gstack.rev;
          superpowersRev = superpowers.rev;
        };
      mkLinuxHome =
        system:
        home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor system;
          extraSpecialArgs = homeSpecialArgsFor system {
            username = linuxUsername;
            homeDirectory = linuxHomeDirectory;
            herdrPackage = herdr.packages.${system}.default;
          };
          modules = [
            ./home.nix
            { programs.home-manager.enable = true; }
          ];
        };
    in
    {
      darwinConfigurations."mac" = nix-darwin.lib.darwinSystem {
        specialArgs = {
          username = darwinUsername;
          homeDirectory = darwinHomeDirectory;
        };
        modules = [
          ./configuration.nix
          nix-homebrew.darwinModules.nix-homebrew
          home-manager.darwinModules.home-manager
          ({ config, ... }: {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = homeSpecialArgsFor config.nixpkgs.hostPlatform.system {
              username = darwinUsername;
              homeDirectory = darwinHomeDirectory;
              herdrPackage = null;
            };
            home-manager.users.${darwinUsername} = import ./home.nix;
          })
        ];
      };
      homeConfigurations = {
        linux-x86_64 = mkLinuxHome "x86_64-linux";
        linux-aarch64 = mkLinuxHome "aarch64-linux";
        # Compatibility aliases for machines provisioned before the targets
        # became distro-neutral. They point at the same configurations.
        ubuntu-x86_64 = mkLinuxHome "x86_64-linux";
        ubuntu-aarch64 = mkLinuxHome "aarch64-linux";
      };
      packages = forAllSystems (system: {
        ci = ciFor system;
        axi-tools = axiToolsPackageFor system;
        gnhf = gnhfPackageFor system;
        nono = nonoPackageFor system;
        nono-runtime-test = nonoRuntimeTestFor system;
        default = nonoPackageFor system;
      });
      apps = forAllSystems (system: {
        nono-runtime-test = {
          type = "app";
          program = "${nonoRuntimeTestFor system}/bin/nono-runtime-test";
        };
      });
      checks = forAllSystems checksForSystem;

      # Combined formatter: Nix via nixfmt (RFC style), shell via shfmt.
      formatter = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        pkgs.writeShellApplication {
          name = "fmt-tree";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.git
            pkgs.nixfmt
            pkgs.shfmt
          ];
          # git ls-files keeps the formatter on tracked files only, matching
          # the format check's fileset view.
          text = ''
            existing_tracked_files() {
              local path
              git ls-files -z "$1" |
                while IFS= read -r -d $'\0' path; do
                  if [[ -e "$path" ]]; then
                    printf '%s\0' "$path"
                  fi
                done
            }

            existing_tracked_files '*.nix' | xargs -0 -r nixfmt --
            existing_tracked_files '*.sh' | xargs -0 -r shfmt -w -i 2 -ci --
          '';
        }
      );
    };
}
