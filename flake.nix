{
  description = "ADO analysis tools — Python and PowerShell scripts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        pythonEnv = pkgs.python3.withPackages (ps: [
          ps.requests
          ps.pyyaml
        ]);
      in
      {
        devShells.default = pkgs.mkShell {
          name = "ado-analysis";

          packages = [
            pythonEnv
            pkgs.powershell
            pkgs.icu
          ];

          shellHook = ''
            echo "ADO analysis dev shell"
            echo "  python  -> $(python --version)"
            echo "  pwsh    -> $(pwsh --version)"
          '';
        };
      }
    );
}
