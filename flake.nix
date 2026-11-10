{
  description = "pi coding agent built from source, with a CI-maintained model-catalog pin";

  # Upstream release tag. CI rewrites this line when upstream tags a new version.
  inputs.pi-src.url = "git+https://github.com/earendil-works/pi?ref=refs/tags/v1.5.2";
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
          # Second installation path: the published npm tarball, no source
          # checkout and no TypeScript build.
          pi-npm = pkgs.callPackage ./packages/pi-npm.nix { };
          # `nix run` / `nix build` with no attribute should give the path the
          # README recommends: the prebuilt tarball, which cannot fail on a
          # stale model-catalog pin.
          default = self.packages.${system}.pi-npm;
        }
      );

      overlays = {
        default = final: _prev: {
          pi = final.callPackage ./packages/pi.nix { inherit pi-src; };
        };
        npm = final: _prev: {
          pi = final.callPackage ./packages/pi-npm.nix { };
        };
      };

      # Same options in both; the only difference is where the wrapper is
      # installed (home.packages vs environment.systemPackages).
      homeModules = {
        default = import ./modules { inherit self; mode = "home"; };
      };
      homeManagerModules = self.homeModules;

      nixosModules = {
        default = import ./modules { inherit self; mode = "system"; };
      };
    };
}
