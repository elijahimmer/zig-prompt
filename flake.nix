{
  description = "Zig Prompt A tool to make a prompt for input on screen.";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.systems.url = "github:nix-systems/default-linux";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.flake-utils.inputs.systems.follows = "systems";

  outputs = {
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in
      with pkgs; {
        formatter = alejandra;
        devShells.default = mkShell {
          nativeBuildInputs = [zig];
          buildInputs = [wayland];
        };
      });
}
