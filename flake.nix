{
  description = "Declarative claude-code-bootstrap for home-manager (NixOS)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = nixpkgs.lib.genAttrs systems;
    in
    {
      homeManagerModules.default = import ./modules/claude-code.nix;

      # packages added in Task 5

      # Tools the maintenance skill needs, guaranteed present via `nix develop`.
      devShells = forAll (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in { default = pkgs.mkShell { packages = [ pkgs.gh pkgs.git ]; }; });

      checks = forAll (system: {
        example = (home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [ self.homeManagerModules.default ./examples/home.nix ];
        }).activationPackage;
      });
    };
}
