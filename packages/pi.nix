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
  # Only the pin file is replaced; everything else comes from the upstream tree.
  pinnedPkg = runCommandLocal "pi-nix-pinned" { } ''
    mkdir -p $out/nix
    cp ${pi-src}/nix/package.nix $out/nix/package.nix
    cp ${./pi-model-catalog.json} $out/nix/model-catalog.json
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
