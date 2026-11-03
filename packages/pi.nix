{
  lib,
  stdenv,
  runCommandLocal,
  nodejs_22,
  fetchurl,
  importNpmLock,
  makeWrapper,
  autoPatchelfHook,
  libxcb,
  fd,
  ripgrep,
  wl-clipboard,
  xclip,
  pi-src,
}:

let
  # A copy of upstream's nix/ dir with our own model-catalog pin, plus a repair
  # for the release tag we build from.
  #
  # Upstream v1.5.0 omits @earendil-works/pi-schema in two places of
  # nix/package.nix: installPhase never packs packages/schema, and
  # packageSourceOverrides has no entry for it. Its install-lock still ships
  # that package without an integrity field, so evaluation needs the override
  # and the build needs the tarball. main fixed both; the tag did not.
  #
  # Each repair is conditional, so a later tag that already carries it is used
  # unchanged.
  pinnedPkg = runCommandLocal "pi-nix-pinned" { } ''
    mkdir -p $out/nix
    cp ${pi-src}/nix/package.nix $out/nix/package.nix
    cp ${./pi-model-catalog.json} $out/nix/model-catalog.json

    pkg=$out/nix/package.nix

    # 1. Pack the schema workspace package alongside the other seven.
    if ! grep -qF 'pack_package packages/schema schema' "$pkg"; then
      anchor='      pack_package packages/telemetry telemetry'
      grep -qF "$anchor" "$pkg" || {
        echo "cannot locate the pack_package anchor" >&2
        exit 1
      }
      sed -i "\|$anchor|a\\
          pack_package packages/schema schema" "$pkg"
    fi

    # 2. Point the pi-schema module at that tarball.
    if ! grep -qF '"node_modules/@earendil-works/pi-schema"' "$pkg"; then
      anchor='      "node_modules/@earendil-works/pi-mcp" = workspacePackages + "/mcp.tgz";'
      grep -qF "$anchor" "$pkg" || {
        echo "cannot locate the packageSourceOverrides anchor" >&2
        exit 1
      }
      sed -i "\|$anchor|a\\
          \"node_modules/@earendil-works/pi-schema\" = workspacePackages + \"/schema.tgz\";" "$pkg"
    fi
  '';
in
import (pinnedPkg + "/nix/package.nix") {
  inherit
    lib
    stdenv
    nodejs_22
    fetchurl
    importNpmLock
    makeWrapper
    autoPatchelfHook
    libxcb
    fd
    ripgrep
    wl-clipboard
    xclip
    ;
  source = pi-src;
}
