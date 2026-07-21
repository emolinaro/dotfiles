{
  description = "dotfiles";

  inputs = {
    # Use `github:NixOS/nixpkgs/nixpkgs-26.05-darwin` to use Nixpkgs 26.05.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nixpkgs-linux.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Use `github:nix-darwin/nix-darwin/nix-darwin-26.05` to use Nixpkgs 26.05.
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # Pin Herdr independently so Ubuntu gets the upstream-supported Nix build.
    herdr.url = "github:ogulcancelik/herdr/v0.7.3";
    herdr.inputs.nixpkgs.follows = "nixpkgs-linux";

    # Use Treehouse's upstream-supported package on macOS and Ubuntu.
    treehouse.url = "github:kunchenguid/treehouse/v2.0.1";
    treehouse.inputs.nixpkgs.follows = "nixpkgs";

    # Pin the public Lavish skill; its CLI runs on demand through npx.
    lavish = {
      url = "github:kunchenguid/lavish-axi/lavish-axi-v0.1.42";
      flake = false;
    };

    # Expose chrome-devtools-axi as a global agent skill; its CLI runs on demand through npx.
    chromeDevtoolsAxi = {
      url = "github:kunchenguid/chrome-devtools-axi/chrome-devtools-axi-v0.1.26";
      flake = false;
    };

    # Expose gh-axi as a global agent skill; its CLI runs on demand through npx.
    ghAxi = {
      url = "github:kunchenguid/gh-axi/gh-axi-v0.1.27";
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

  outputs = inputs@{ self, nix-darwin, nix-homebrew, home-manager, nixpkgs, nixpkgs-linux, herdr, treehouse, lavish, chromeDevtoolsAxi, ghAxi, gstack, superpowers }:
  let
    envOr = name: fallback:
      let value = builtins.getEnv name;
      in if value == "" then fallback else value;
    sudoUser = builtins.getEnv "SUDO_USER";
    currentUser = builtins.getEnv "USER";
    darwinUsername =
      if sudoUser != "" && sudoUser != "root" then sudoUser
      else if currentUser != "" && currentUser != "root" then currentUser
      else throw "Unable to determine the non-root macOS user. Run the setup as a sudo-capable user with --impure.";
    darwinHomeDirectory = "/Users/${darwinUsername}";
    ubuntuUsername = envOr "DOTFILES_USERNAME" "ubuntu";
    ubuntuHomeDirectory = envOr "DOTFILES_HOME" "/home/${ubuntuUsername}";
    mkUbuntuHome = system: home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs-linux {
        inherit system;
        config.allowUnfree = true;
      };
      extraSpecialArgs = {
        chromeDevtoolsAxiSkill = "${chromeDevtoolsAxi}/skills/chrome-devtools-axi";
        username = ubuntuUsername;
        homeDirectory = ubuntuHomeDirectory;
        herdrPackage = herdr.packages.${system}.default;
        ghAxiSkill = "${ghAxi}/skills/gh-axi";
        lavishSkill = "${lavish}/skills/lavish";
        treehousePackage = treehouse.packages.${system}.default;
        gstackRev = gstack.rev;
        superpowersSkill = "${superpowers}/skills";
        superpowersRev = superpowers.rev;
      };
      modules = [
        ./home.nix
        { programs.home-manager.enable = true; }
      ];
    };
  in {
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
            ghAxiSkill = "${ghAxi}/skills/gh-axi";
            lavishSkill = "${lavish}/skills/lavish";
            treehousePackage = treehouse.packages.${config.nixpkgs.hostPlatform.system}.default;
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
  };
}
