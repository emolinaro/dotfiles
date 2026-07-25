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

    # Expose the public Lavish skill; its CLI runs on demand through npx.
    lavish = {
      url = "github:kunchenguid/lavish-axi";
      flake = false;
    };

    # Expose chrome-devtools-axi as a global agent skill; its CLI runs on demand through npx.
    chromeDevtoolsAxi = {
      url = "github:kunchenguid/chrome-devtools-axi";
      flake = false;
    };

    # Expose gh-axi as a global agent skill; its CLI runs on demand through npx.
    ghAxi = {
      url = "github:kunchenguid/gh-axi";
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
      gnhfPackageFor = system: (pkgsFor system).callPackage ./packages/gnhf.nix { };
      nonoRuntimeTestFor =
        system:
        (pkgsFor system).callPackage ./tests/nono-runtime.nix {
          inherit agentRegistry;
          nonoPackage = nonoPackageFor system;
          profiles = ./home/.config/nono/profiles;
          wrapperModule = ./runtime/nono-agent-wrappers.nix;
        };
      mkUbuntuHome =
        system:
        home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor system;
          extraSpecialArgs = {
            chromeDevtoolsAxiSkill = "${chromeDevtoolsAxi}/skills/chrome-devtools-axi";
            username = ubuntuUsername;
            homeDirectory = ubuntuHomeDirectory;
            herdrPackage = herdr.packages.${system}.default;
            nonoPackage = nonoPackageFor system;
            ghAxiSkill = "${ghAxi}/skills/gh-axi";
            gnhfPackage = gnhfPackageFor system;
            lavishSkill = "${lavish}/skills/lavish";
            gstackRev = gstack.rev;
            superpowersSkill = "${superpowers}/skills";
            superpowersRev = superpowers.rev;
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
            home-manager.extraSpecialArgs = {
              chromeDevtoolsAxiSkill = "${chromeDevtoolsAxi}/skills/chrome-devtools-axi";
              username = darwinUsername;
              homeDirectory = darwinHomeDirectory;
              herdrPackage = null;
              nonoPackage = nonoPackageFor config.nixpkgs.hostPlatform.system;
              ghAxiSkill = "${ghAxi}/skills/gh-axi";
              gnhfPackage = gnhfPackageFor config.nixpkgs.hostPlatform.system;
              lavishSkill = "${lavish}/skills/lavish";
              gstackRev = gstack.rev;
              superpowersSkill = "${superpowers}/skills";
              superpowersRev = superpowers.rev;
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
        gnhf-agent-launchers = (pkgsFor system).callPackage ./tests/gnhf-agent-launchers.nix {
          launcherModule = ./runtime/gnhf-agent-launchers.nix;
        };
        gnhf-home =
          if (pkgsFor system).stdenv.hostPlatform.isLinux then
            (pkgsFor system).callPackage ./tests/gnhf-home.nix {
              gnhfPackage = gnhfPackageFor system;
              homeConfig = (mkUbuntuHome system).config;
            }
          else
            (pkgsFor system).runCommand "gnhf-home-not-linux" { } ''
              touch "$out"
            '';
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
        nono-runtime-driver = nonoRuntimeTestFor system;
      });
    };
}
