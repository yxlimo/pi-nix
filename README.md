# pi-nix

`pi` built from source on Nix, with a model-catalog pin that CI keeps current.

## Why this exists

Upstream `earendil-works/pi` ships a flake, but its `nix/package.nix` hydrates
model data from a catalog pinned in `nix/model-catalog.json` — a static file.
Only upstream's own CI replaces that pin before building:

```yaml
# .github/workflows/nix.yml (upstream)
- run: node scripts/update-model-catalog-pin.mjs --if-stale
- run: printf '{"revision":"%s"}' "$REVISION" > nix/model-catalog.json
- run: nix build -L .
```

External consumers never run those steps. They get the static file, which goes
stale as pi.dev publishes new catalogs (providers gain or lose classifier or
api groups). When the pinned data lacks a group the code needs, the generated
types collapse and the build dies:

```
src/providers/github-copilot.ts:33 TS2322
Type 'unknown[]' is not assignable to type 'readonly ProviderModel<...>[]'
```

Measured 2026-11-03 at commit `d71c66e0`: upstream CI succeeded, while
`nix build github:earendil-works/pi#pi` failed on the stale repo pin. The repo
pin at that commit listed 27 `github-copilot` entries, all `chat`; the catalog
upstream CI substituted had 28, including one `classifier/typesafe-system-one`.

This repo runs the same refresh in its own CI, then rebuilds and smoke-tests
before committing. The flake input is buildable at any point in time.

## Usage

```nix
{
  inputs.pi-nix.url = "github:yxlimo/pi-nix";

  # either as a package
  environment.systemPackages = [ inputs.pi-nix.packages.${system}.pi ];

  # or as an overlay
  nixpkgs.overlays = [ inputs.pi-nix.overlays.default ];
}
```

## How the pin stays valid

Same discovery endpoint upstream CI uses:

```
GET /api/models?types=chat,image,classifier
  -> header x-pi-model-catalog-revision is the current revision
  -> body sha256 must equal it (content-addressed)
```

`.github/workflows/update-pin.yml` runs daily, plus on manual dispatch:

1. `nix flake update pi-src` — follow upstream `stable`
2. `scripts/update-pin.py` — refresh `packages/pi-model-catalog.json`
3. `nix build .#pi` — prove it works
4. smoke-test `pi --version` / `pi --help`
5. commit, only if the build succeeded

A failed build leaves the repo on the last known-good state, so consumers never
pull a broken pin.

## Layout

| Path | Purpose |
|---|---|
| `flake.nix` | follows upstream `stable` + nixpkgs-unstable |
| `packages/pi.nix` | replaces only the pin file, reuses upstream `nix/package.nix` |
| `packages/pi-model-catalog.json` | the pin CI maintains |
| `scripts/update-pin.py` | fetches and validates the current revision |

## Notes

`packages/pi.nix` synthesizes a two-file directory holding upstream's
`nix/package.nix` beside the refreshed `packages/pi-model-catalog.json`, then
imports that. Upstream reads only `model-catalog.json` relative to itself
(`lib.importJSON ./model-catalog.json`); every other path goes through
`source + "/..."`, so `source` still points at the untouched upstream tree and
nothing is copied.
