{
  description = "CP2K - Quantum chemistry and solid state physics program";

  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";

    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }: flake-utils.lib.eachDefaultSystem
    (system:
      let
        overlay = import ./nix/overlay.nix;
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ overlay ];
        };
      in
      {
        packages.default = pkgs.cp2k;

        devShells.default = with pkgs; mkShell {
          buildInputs = [
            nixpkgs-fmt
            fortls
            fprettify
          ]
          ++ cp2k.nativeBuildInputs
          ++ cp2k.buildInputs
          ++ cp2k.propagatedBuildInputs
          ;

          shellHook =
            cp2k.configurePhase
            # + cp2k.postPatch
          ;
        };
      }
    ) // {
    overlays.default = import ./nix/overlay.nix;
  };
}
