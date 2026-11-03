{
  description = "pi coding agent built from source, with a CI-maintained model-catalog pin";

  # Upstream release tag. CI rewrites this line when upstream tags a new version.
  inputs.pi-src.url = "git+https://github.com/earendil-works/pi?ref=refs/tags/v1.5.0";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs, pi-src }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          pi = pkgs.callPackage ./packages/pi.nix { inherit pi-src; };
          default = self.packages.${system}.pi;
        }
      );

      overlays.default = final: _prev: {
        pi = final.callPackage ./packages/pi.nix { inherit pi-src; };
      };
    };
}
