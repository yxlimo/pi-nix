#!/usr/bin/env python3
"""Point the npm package at a given pi version.

Rewrites the version and tarball hash in packages/pi-npm.nix and regenerates
the install lockfile in npm/ (see gen-npm-lock.py for what that involves).

Usage:
    python3 scripts/update-npm-artifact.py 1.5.0
    python3 scripts/update-npm-artifact.py            # keep the current version
"""

import hashlib
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PKG_NIX = os.path.join(ROOT, "packages", "pi-npm.nix")
TARBALL = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-{version}.tgz"


def current_version():
    text = open(PKG_NIX, encoding="utf-8").read()
    match = re.search(r'^\s*version = "([^"]+)";', text, re.MULTILINE)
    if not match:
        raise SystemExit("cannot find the version line in packages/pi-npm.nix")
    return match.group(1)


def download(url, tries=8):
    last = None
    for attempt in range(tries):
        try:
            with urllib.request.urlopen(url, timeout=300) as response:
                return response.read()
        except Exception as exc:  # noqa: BLE001 - retried below
            last = exc
            time.sleep(2 + attempt * 3)
    raise SystemExit(f"{url}: {last}")


def sri_hash(body):
    digest = hashlib.sha256(body).digest()
    import base64

    return "sha256-" + base64.b64encode(digest).decode()


def main():
    version = sys.argv[1] if len(sys.argv) > 1 else current_version()
    url = TARBALL.format(version=version)

    print(f"[npm-artifact] {version}: downloading tarball")
    body = download(url)
    new_hash = sri_hash(body)

    text = open(PKG_NIX, encoding="utf-8").read()
    text = re.sub(r'^(\s*version = ")[^"]+(";)', rf"\g<1>{version}\g<2>", text, count=1, flags=re.MULTILINE)
    text = re.sub(r'^(\s*hash = ")[^"]+(";)', rf"\g<1>{new_hash}\g<2>", text, count=1, flags=re.MULTILINE)
    with open(PKG_NIX, "w", encoding="utf-8") as fh:
        fh.write(text)
    print(f"[npm-artifact] tarball hash {new_hash}")

    subprocess.run(
        [sys.executable, os.path.join(ROOT, "scripts", "gen-npm-lock.py"), version],
        check=True,
    )


if __name__ == "__main__":
    main()
