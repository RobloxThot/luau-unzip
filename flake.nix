{
  description = "luau-unzip development environment";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-24.11";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      devpkgs = import ./dev.nix {
        inherit pkgs;
      };
    in
    {
      packages.${system}.devShell = devpkgs;
      defaultPackage.${system} = devpkgs;
    };
}

