{
  description = "dotfiles";

  inputs = {
    # Keep the core Nix modules on matching release branches.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nixpkgs-linux.url = "github:NixOS/nixpkgs/nixos-26.05";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # Use Herdr independently so Ubuntu gets the upstream-supported Nix build.
    herdr.url = "github:ogulcancelik/herdr";
    herdr.inputs.nixpkgs.follows = "nixpkgs-linux";

    # Expose the public Lavish skill.
    lavish = {
      url = "github:kunchenguid/lavish-axi";
      flake = false;
    };

    # Expose chrome-devtools-axi as a global agent skill.
    chromeDevtoolsAxi = {
      url = "github:kunchenguid/chrome-devtools-axi";
      flake = false;
    };

    # Expose gh-axi as a global agent skill.
    ghAxi = {
      url = "github:kunchenguid/gh-axi";
      flake = false;
    };

    # Expose tasks-axi as a global agent skill.
    tasksAxi = {
      url = "github:kunchenguid/tasks-axi";
      flake = false;
    };

    # Expose quota-axi as a global agent skill.
    quotaAxi = {
      url = "github:kunchenguid/quota-axi";
      flake = false;
    };

    # Lock gnhf so rebuilds do not silently pull new behavior.
    gnhf = {
      url = "github:kunchenguid/gnhf";
      flake = false;
    };

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
      nixpkgs-linux,
      herdr,
      lavish,
      chromeDevtoolsAxi,
      ghAxi,
      tasksAxi,
      quotaAxi,
      gnhf,
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
      ubuntuUsername = envOr "DOTFILES_USERNAME" "ubuntu";
      ubuntuHomeDirectory = envOr "DOTFILES_HOME" "/home/${ubuntuUsername}";
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
      nonoPackageFor = system: (pkgsFor system).callPackage ./packages/nono.nix { };
      axiToolsPackageFor =
        system:
        let
          pkgs = pkgsFor system;
          axiTools = [
            {
              pname = "chrome-devtools-axi";
              src = chromeDevtoolsAxi;
              entryPoint = "dist/bin/chrome-devtools-axi.js";
              pnpmDepsHash = "sha256-UPNA+pa9vaq3S9bH6s7yVoqgtsPJ7iu7eRFfTkpS8UU=";
            }
            {
              pname = "gh-axi";
              src = ghAxi;
              entryPoint = "dist/bin/gh-axi.js";
              pnpmDepsHash = "sha256-snoKB2/sZmuvqFtmUAVPcyL6hcGX7+EGRN+49wwPX1o=";
            }
            {
              pname = "lavish-axi";
              src = lavish;
              entryPoint = "dist/cli.mjs";
              pnpmDepsHash = "sha256-DLCtgOtlPHe3GA1P0xfjJ1X1eJhFkH/hQcoEt+5b164=";
            }
            {
              pname = "quota-axi";
              src = quotaAxi;
              entryPoint = "dist/bin/quota-axi.js";
              pnpmDepsHash = "sha256-l3bTF7qXLSfS7JNbJfM8RiaYy7vkzrkJoIDRYdiG9R8=";
            }
            {
              pname = "tasks-axi";
              src = tasksAxi;
              entryPoint = "dist/bin/tasks-axi.js";
              pnpmDepsHash = "sha256-wxguqzq/KuXekU2KlGJUU9IPJMgUjLZyuscNtZysXfo=";
            }
          ];
          mkAxiTool =
            {
              pname,
              src,
              entryPoint,
              pnpmDepsHash,
            }:
            pkgs.stdenvNoCC.mkDerivation {
              inherit pname src;
              version = (builtins.fromJSON (builtins.readFile "${src}/package.json")).version;

              pnpmDeps = pkgs.fetchPnpmDeps {
                inherit pname src;
                pnpm = pkgs.pnpm_11;
                fetcherVersion = 4;
                hash = pnpmDepsHash;
              };

              nativeBuildInputs = [
                pkgs.makeWrapper
                pkgs.nodejs
                pkgs.pnpm_11
                pkgs.pnpmConfigHook
              ];

              buildPhase = ''
                runHook preBuild
                pnpm build
                runHook postBuild
              '';

              installPhase = ''
                runHook preInstall
                install -dm755 "$out/lib/node_modules/${pname}"
                cp -r dist node_modules package.json "$out/lib/node_modules/${pname}/"
                makeWrapper ${pkgs.lib.getExe pkgs.nodejs} "$out/bin/${pname}" --add-flags "$out/lib/node_modules/${pname}/${entryPoint}"
                runHook postInstall
              '';
            };
        in
        pkgs.symlinkJoin {
          name = "axi-tools";
          paths = map mkAxiTool axiTools;
        };
      gnhfPackageFor =
        system:
        let
          pkgs = pkgsFor system;
          src = gnhf;
          version = (builtins.fromJSON (builtins.readFile "${src}/package.json")).version;
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = "gnhf";
          inherit src version;

          pnpmDeps = pkgs.fetchPnpmDeps {
            pname = "gnhf";
            inherit src;
            pnpm = pkgs.pnpm_11;
            fetcherVersion = 4;
            hash = "sha256-kQHYvZ8LNHGw1pPuTnOTUn26yUY8TmgA0+BO2+cSvLY=";
          };

          nativeBuildInputs = [
            pkgs.makeWrapper
            pkgs.nodejs
            pkgs.pnpm_11
            pkgs.pnpmConfigHook
          ];

          buildPhase = ''
            runHook preBuild
            pnpm build
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            pnpm prune --prod
            install -dm755 "$out/lib/node_modules/gnhf"
            cp -r dist node_modules package.json "$out/lib/node_modules/gnhf/"
            makeWrapper ${pkgs.lib.getExe pkgs.nodejs} "$out/bin/gnhf" --add-flags "$out/lib/node_modules/gnhf/dist/cli.mjs"
            runHook postInstall
          '';

          meta = {
            description = "Pinned GNHF CLI; pick the backend with --agent";
            homepage = "https://github.com/kunchenguid/gnhf";
            license = pkgs.lib.licenses.mit;
            mainProgram = "gnhf";
            platforms = [
              "aarch64-darwin"
              "x86_64-darwin"
              "aarch64-linux"
              "x86_64-linux"
            ];
          };
        };
      nonoRuntimeTestFor =
        system:
        (pkgsFor system).callPackage ./tests/nono-runtime.nix {
          inherit agentRegistry;
          nonoPackage = nonoPackageFor system;
          profiles = ./home/.config/nono/profiles;
          wrapperModule = ./runtime/nono-agent-wrappers.nix;
        };
      # Shared Home Manager special arguments for both platforms; call sites
      # pass only their per-platform deltas.
      homeSpecialArgsFor =
        system:
        {
          username,
          homeDirectory,
          herdrPackage,
        }:
        {
          inherit username homeDirectory herdrPackage;
          axiToolsPackage = axiToolsPackageFor system;
          gnhfPackage = gnhfPackageFor system;
          nonoPackage = nonoPackageFor system;
          chromeDevtoolsAxiSkill = "${chromeDevtoolsAxi}/skills/chrome-devtools-axi";
          ghAxiSkill = "${ghAxi}/skills/gh-axi";
          lavishSkill = "${lavish}/skills/lavish";
          quotaAxiSkill = "${quotaAxi}/skills/quota-axi";
          superpowersSkill = "${superpowers}/skills";
          tasksAxiSkill = "${tasksAxi}/skills/tasks-axi";
          gstackRev = gstack.rev;
          superpowersRev = superpowers.rev;
        };
      mkUbuntuHome =
        system:
        home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor system;
          extraSpecialArgs = homeSpecialArgsFor system {
            username = ubuntuUsername;
            homeDirectory = ubuntuHomeDirectory;
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
        ubuntu-x86_64 = mkUbuntuHome "x86_64-linux";
        ubuntu-aarch64 = mkUbuntuHome "aarch64-linux";
      };
      packages = forAllSystems (system: {
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
      checks = forAllSystems (system: {
        axi-tools = (pkgsFor system).callPackage ./tests/axi-tools.nix {
          axiToolsPackage = axiToolsPackageFor system;
        };
        gnhf-package = (pkgsFor system).callPackage ./tests/gnhf-package.nix {
          gnhfPackage = gnhfPackageFor system;
        };
        gstack-checkout-migration = (pkgsFor system).callPackage ./tests/gstack-checkout-migration.nix {
          migrationPackage = (pkgsFor system).callPackage ./runtime/gstack-checkout-migration.nix { };
        };
        nono-package = (pkgsFor system).callPackage ./tests/nono-package.nix {
          nonoPackage = nonoPackageFor system;
        };
        nono-agent-wrappers = (pkgsFor system).callPackage ./tests/nono-agent-wrappers.nix {
          inherit agentRegistry;
          profiles = ./home/.config/nono/profiles;
          wrapperModule = ./runtime/nono-agent-wrappers.nix;
        };
        nono-home-command-surface =
          if (pkgsFor system).stdenv.hostPlatform.isLinux then
            (pkgsFor system).callPackage ./tests/nono-home-command-surface.nix {
              inherit agentRegistry;
              homePath = (mkUbuntuHome system).config.home.path;
            }
          else
            (pkgsFor system).runCommand "nono-home-command-surface-not-linux" { } ''
              touch "$out"
            '';
        nono-profiles = (pkgsFor system).callPackage ./tests/nono-profiles.nix {
          inherit agentRegistry;
          nonoPackage = nonoPackageFor system;
          profiles = ./home/.config/nono/profiles;
        };
        nono-runtime-test = nonoRuntimeTestFor system;
      });
    };
}
