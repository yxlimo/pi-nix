# pi-nix

`pi` packaged for Nix, two ways: built from source, or unpacked from the
published npm tarball. Both are kept current by CI.

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

## Two installation paths

| Attribute | What it installs | Needs | Fails when |
|---|---|---|---|
| `pi` | upstream source, compiled with `tsc` | the model-catalog pin to be fresh | catalog data drifts from the code's type expectations |
| `pi-npm` | the published npm tarball, already compiled | nothing but the tarball | never from TypeScript |

`pi-npm` sidesteps the entire catalog problem: the tarball is whatever upstream
published, compiled by them. It costs reproducibility of the build itself (you
trust their artifact) and gets no source audit. `pi` keeps the source path
working and is what upstream's own CI validates.

Prefer `pi-npm` unless you specifically want to build from source.

### Why the npm path needs a generated lockfile

The npm tarball ships compiled output but no `node_modules` — its 22 runtime
dependencies still have to be fetched. Nix insists on a lockfile with an
`integrity` hash per dependency, and pi's official installer lockfile omits that
field on all eight `@earendil-works/*` packages
([earendil-works/pi#4315](https://github.com/earendil-works/pi/issues/4315)).

Upstream's own release metadata has them, though. `scripts/gen-npm-lock.py`
takes the installer lockfile and fills those eight fields from
`GET /api/installer/releases/<version>`, which publishes every package with its
`integrity`. Both values come from the same release; nothing is recomputed.

## Usage

```nix
{
  inputs.pi-nix.url = "github:yxlimo/pi-nix";

  # prebuilt, recommended
  environment.systemPackages = [ inputs.pi-nix.packages.${system}.pi-npm ];

  # or from source
  environment.systemPackages = [ inputs.pi-nix.packages.${system}.pi ];

  # overlays work the same way
  nixpkgs.overlays = [ inputs.pi-nix.overlays.npm ];    # or overlays.default
}
```

## How the pin stays valid

Same discovery endpoint upstream CI uses:

```
GET /api/models?types=chat,image,classifier
  -> header x-pi-model-catalog-revision is the current revision
  -> body sha256 must equal it (content-addressed)
```

`.github/workflows/update.yml` runs daily, plus on manual dispatch:

1. detect the newest upstream release tag and point `pi-src` at it
2. `scripts/update-pin.py` — refresh `packages/pi-model-catalog.json`
3. `scripts/update-npm-artifact.py` — refresh the tarball hash and lockfile
4. `nix build .#pi` and `nix build .#pi-npm`
5. smoke-test both: `pi --version` / `pi --help`
6. verify the built version matches the upstream tag
7. commit, then tag this repo with the same version

Versions track upstream tags exactly: nothing is published here that upstream
has not released.

A failed build leaves the repo on the last known-good state, so consumers never
pull a broken pin.

## Layout

| Path | Purpose |
|---|---|
| `flake.nix` | follows the newest upstream release tag + nixpkgs-unstable |
| `packages/pi.nix` | replaces only the pin file, reuses upstream `nix/package.nix` |
| `packages/pi-model-catalog.json` | the pin CI maintains |
| `packages/pi-npm.nix` | prebuilt npm tarball + generated lockfile |
| `npm/package-lock.json` | installer lockfile with the eight missing hashes filled |
| `scripts/update-pin.py` | fetches and validates the current catalog revision |
| `scripts/gen-npm-lock.py` | rebuilds `npm/` from a release |
| `scripts/update-npm-artifact.py` | bumps version, tarball hash, and lockfile |

## Repair applied to the source path

Upstream `v1.5.0` omits `@earendil-works/pi-schema` from `nix/package.nix` in
both places that must agree: `installPhase` never packs `packages/schema`, and
`packageSourceOverrides` has no entry for it, while the install lock ships that
package without an integrity field. Evaluation failed on the missing integrity;
patching only the override then failed on `schema.tgz` ENOENT. Both repairs are
applied conditionally, so a tag that already carries them is used untouched.

## Notes

`packages/pi.nix` synthesizes a two-file directory holding upstream's
`nix/package.nix` beside the refreshed `packages/pi-model-catalog.json`, then
imports that. Upstream reads only `model-catalog.json` relative to itself
(`lib.importJSON ./model-catalog.json`); every other path goes through
`source + "/..."`, so `source` still points at the untouched upstream tree and
nothing is copied.
