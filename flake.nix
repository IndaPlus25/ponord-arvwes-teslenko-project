{
  description = "Zig Template";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        nativeBuildInputs = with pkgs; [
          zig
          zls
        ];

        buildInputs = with pkgs; [
          sdl3
        ];
      in {
        devShells.default = pkgs.mkShell {
          inherit nativeBuildInputs buildInputs;
            shellHook = ''
              export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath (with pkgs; [
                libGL
                wayland
                libxkbcommon
                libX11
                libXcursor
                libXrandr
                libXi
              ])}:$LD_LIBRARY_PATH
            '';
        };

        packages.default = pkgs.stdenv.mkDerivation {
          pname = "wip non euclidian renderer";
          version = "0.0.0";
          src = ./src;

          nativeBuildInputs =
            nativeBuildInputs
            ++ [
              pkgs.zig.hook
            ];
          inherit buildInputs;
        };
      }
    );
}
