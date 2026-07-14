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
  };

  outputs = inputs@{ self, nix-darwin, nix-homebrew, home-manager, nixpkgs, nixpkgs-linux, herdr }:
  let
    envOr = name: fallback:
      let value = builtins.getEnv name;
      in if value == "" then fallback else value;
    ubuntuUsername = envOr "DOTFILES_USERNAME" "ubuntu";
    ubuntuHomeDirectory = envOr "DOTFILES_HOME" "/home/${ubuntuUsername}";
    mkUbuntuHome = system: home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs-linux {
        inherit system;
        config.allowUnfree = true;
      };
      extraSpecialArgs = {
        username = ubuntuUsername;
        homeDirectory = ubuntuHomeDirectory;
        herdrPackage = herdr.packages.${system}.default;
      };
      modules = [
        ./home.nix
        { programs.home-manager.enable = true; }
      ];
    };
  in {
    darwinConfigurations."mac" = nix-darwin.lib.darwinSystem {
      modules = [ 
        ./configuration.nix 
        nix-homebrew.darwinModules.nix-homebrew
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = {
            username = "molinaro";
            homeDirectory = "/Users/molinaro";
            herdrPackage = null;
          };
          home-manager.users.molinaro = import ./home.nix;
        }
      ];
    };
    homeConfigurations = {
      ubuntu-x86_64 = mkUbuntuHome "x86_64-linux";
      ubuntu-aarch64 = mkUbuntuHome "aarch64-linux";
    };
  };
}
