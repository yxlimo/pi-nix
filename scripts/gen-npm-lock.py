#!/usr/bin/env python3
"""Generate the npm lockfile used by the prebuilt-tarball package.

Pi publishes two official artifacts per release:

  GET /api/installer/releases/<version>/package-lock.json
      npm lockfile for the install tree. Eight @earendil-works/* entries
      (`node_modules/...`) have `resolved` but no `integrity`.

  GET /api/installer/releases/<version>
      release metadata. Every published package carries its `integrity`
      hash here, including those eight.

Nix's `prefetch-npm-deps` / `importNpmLock` require an integrity hash on every
non-git dependency, so the second artifact supplies the values the first one
omits. Nothing is invented or recomputed: both fields come from the same
release, and the hashes are the ones upstream publishes.

Output: npm/package-lock.json (and npm/package.json) in this repository.

Usage:
    python3 scripts/gen-npm-lock.py [version]
"""

import json
import os
import sys
import time
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTDIR = os.path.join(REPO, "npm")
DEFAULT_VERSION = "1.5.0"


def fetch_json(url, tries=8):
    last = None
    for attempt in range(tries):
        try:
            with urllib.request.urlopen(url, timeout=120) as response:
                return json.load(response)
        except Exception as exc:  # noqa: BLE001 - retried below
            last = exc
            time.sleep(2 + attempt * 3)
    raise SystemExit(f"{url}: {last}")


def main():
    version = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_VERSION
    base = f"https://pi.dev/api/installer/releases/{version}"

    lock = fetch_json(f"{base}/package-lock.json")
    release = fetch_json(base)

    metadata = {pkg["name"]: pkg for pkg in release.get("packages", [])}
    if release.get("version") != version:
        raise SystemExit(f"release metadata reports {release.get('version')}, expected {version}")

    filled = []
    for path, entry in lock["packages"].items():
        if not path or entry.get("integrity") or not entry.get("resolved"):
            continue
        # node_modules/@earendil-works/pi-ai -> @earendil-works/pi-ai
        name = path.split("node_modules/", 1)[1]
        source = metadata.get(name)
        if not source or not source.get("integrity"):
            raise SystemExit(f"release metadata has no integrity for {name}")
        entry["integrity"] = source["integrity"]
        filled.append(name)

    missing = [
        path
        for path, entry in lock["packages"].items()
        if path and entry.get("resolved") and not entry.get("integrity")
    ]
    if missing:
        raise SystemExit("still missing integrity: " + ", ".join(missing))

    os.makedirs(OUTDIR, exist_ok=True)
    with open(os.path.join(OUTDIR, "package-lock.json"), "w", encoding="utf-8") as fh:
        json.dump(lock, fh, indent=2, sort_keys=True)
        fh.write("\n")
    with open(os.path.join(OUTDIR, "package.json"), "w", encoding="utf-8") as fh:
        json.dump(lock["packages"][""], fh, indent=2, sort_keys=True)
        fh.write("\n")

    print(f"[npm-lock] {version}: filled {len(filled)} integrity field(s): {' '.join(filled)}")
    print(f"[npm-lock] wrote {OUTDIR}/package-lock.json")


if __name__ == "__main__":
    main()
