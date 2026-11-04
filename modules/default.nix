# Shared implementation of the pi module.
#
# The wrapper is the point of this module: pi writes to its own configuration
# (`pi mcp add` edits mcp.json, `pi install` edits settings.json), so the files
# in ~/.pi/agent cannot be read-only symlinks into the Nix store. Instead the
# declared values are merged into the real files at launch, and declared keys
# win while everything else in the file is kept.
{ self, mode }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  optionPath = [
    "programs"
    "pi"
    "coding-agent"
  ];
  cfg = lib.attrByPath optionPath { } config;
  inherit (pkgs.stdenv.hostPlatform) system;

  settingsJson =
    if cfg.settings == { } then null else pkgs.writeText "pi-settings.json" (builtins.toJSON cfg.settings);

  mcpJson = if cfg.mcp == { } then null else pkgs.writeText "pi-mcp.json" (builtins.toJSON cfg.mcp);

  envPrelude = lib.concatStrings (
    lib.mapAttrsToList
      (name: v:
        if v ? file then
          # Missing file: skip the variable rather than refusing to start pi.
          ''if [ -r ${lib.escapeShellArg v.file} ]; then export ${name}="$(cat ${lib.escapeShellArg v.file})"; fi'' + "\n"
        else
          ''export ${name}=${lib.escapeShellArg v.value}'' + "\n")
      cfg.environment
  );

  modelsPrelude = lib.optionalString (cfg.models != null) ''
    # An earlier version symlinked this to the store: replace it with a real file.
    # (`[ -L x ] && rm` would abort the script under `set -e` when the test fails.)
    if [ -L "$PI_CODING_AGENT_DIR/models.json" ]; then
      rm -f "$PI_CODING_AGENT_DIR/models.json"
    fi
    if [ ! -f "$PI_CODING_AGENT_DIR/models.json" ]; then
      mkdir -p "$PI_CODING_AGENT_DIR"
      install -m 0600 ${cfg.models} "$PI_CODING_AGENT_DIR/models.json"
    fi
  '';

  mergePrelude = filename: patch:
    let
      fn = "merge_${lib.replaceStrings [ "." ] [ "_" ] filename}";
    in
    lib.optionalString (patch != null) ''
      ${fn}() {
        file="$PI_CODING_AGENT_DIR/${filename}"
        patch=${patch}
        if [ -L "$file" ]; then rm -f "$file"; fi
        mkdir -p "$PI_CODING_AGENT_DIR"
        tmp="$(mktemp "$PI_CODING_AGENT_DIR/.${filename}.XXXXXX")"
        if [ -f "$file" ]; then
          ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$file" "$patch" > "$tmp"
        else
          printf '{}' | ${pkgs.jq}/bin/jq -s '.[0] * .[1]' - "$patch" > "$tmp"
        fi
        chmod 0600 "$tmp"
        if [ -f "$file" ] && cmp -s "$tmp" "$file"; then
          rm -f "$tmp"
        else
          mv "$tmp" "$file"
        fi
      }
      ${fn}
    '';

  wrapped = pkgs.writeShellScriptBin "pi" ''
    set -eu
    # Exported first: `environment` may itself set PI_CODING_AGENT_DIR, and the
    # rest of this script has to use the value that ends up in effect.
    ${envPrelude}
    PI_CODING_AGENT_DIR="''${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
    export PI_CODING_AGENT_DIR

    ${modelsPrelude}
    ${mergePrelude "settings.json" settingsJson}
    ${mergePrelude "mcp.json" mcpJson}

    exec ${lib.getExe cfg.package} "$@"
  '';
in
{
  options = lib.setAttrByPath optionPath {
    enable = lib.mkEnableOption "pi coding agent, with declarative configuration";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${system}.pi-npm;
      defaultText = lib.literalExpression "pi-nix.packages.<system>.pi-npm";
      description = ''
        The pi package to wrap. Defaults to this flake's prebuilt `pi-npm`
        attribute; set it to `pi-nix.packages.<system>.pi` to build from source.
      '';
    };

    models = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Contents of `models.json`. Installed once, when the file does not exist
        yet; afterwards pi's (or your) edits are left alone.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Declarative part of `settings.json`, merged recursively at launch.
        Declared values win; other keys already in the file are kept.
        `settings.packages` is how you declare pi packages (plugins).
      '';
      example = lib.literalExpression ''
        {
          packages = [ "npm:@cortexkit/pi-magic-context" ];
        }
      '';
    };

    mcp = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Declarative part of `mcp.json`, merged recursively at launch.
        Declared values win; other servers already in the file are kept.
        Removing a declaration does not delete the value from the file.
      '';
      example = lib.literalExpression ''
        {
          mcpServers.docs = {
            url = "https://example.com/mcp";
            headers.Authorization = "Bearer ''${DOCS_TOKEN}";
          };
        }
      '';
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          file = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Read this file at launch and export its contents.";
          };
          value = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              Literal value. It ends up in the Nix store, which is
              world-readable, so do not put secrets here.
            '';
          };
        };
      });
      default = { };
      description = ''
        Environment variables exported before pi starts. Use `file` for
        anything that comes from a secret manager at runtime, `value` for
        plain literals.
      '';
      example = lib.literalExpression ''
        {
          PI_CODING_AGENT_DIR.value = "/home/user/.pi/agent";
          OPENAI_API_KEY.file = config.sops.secrets.openai-api-key.path;
        }
      '';
    };

    finalPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      description = "The wrapped pi, for `lib.mkCodingAgent`-style consumers.";
      default = wrapped;
      defaultText = lib.literalExpression "<pi with the declared configuration merged in>";
    };
  };

  config = lib.mkIf cfg.enable (
      if mode == "home" then
        { home.packages = [ cfg.finalPackage ]; }
      else
        { environment.systemPackages = [ cfg.finalPackage ]; }
  );
}
