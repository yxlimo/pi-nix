#!/usr/bin/env python3
"""Refresh the pi model-catalog pin. See README.md for why this is needed."""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PIN = os.path.join(ROOT, "packages", "pi-model-catalog.json")
TYPES = "chat,image,classifier"
REV_RE = re.compile(r"^sha256-[0-9a-f]{64}$")
DISCOVERY = f"https://pi.dev/api/models?types={TYPES}"


def fetch(url, tries=8):
    """GET url with curl. Returns (headers, body), retrying transient failures."""
    last = ""
    for attempt in range(tries):
        proc = subprocess.run(
            ["curl", "-sS", "-D", "-", "--max-time", "180", url], capture_output=True
        )
        if proc.returncode == 0 and proc.stdout:
            raw = proc.stdout
            sep = raw.find(b"\r\n\r\n")
            if sep < 0:
                sep = raw.find(b"\n\n")
            head, body = raw[:sep], raw[sep:].lstrip(b"\r\n")
            headers = {}
            for line in head.decode("latin-1").splitlines():
                if ":" in line:
                    key, value = line.split(":", 1)
                    headers[key.strip().lower()] = value.strip()
            return headers, body
        last = proc.stderr.decode(errors="replace")[:200]
        print(f"attempt {attempt + 1} failed: {last}", file=sys.stderr)
    raise SystemExit(f"cannot fetch {url}: {last}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true", help="write even if unchanged")
    ap.add_argument("--check", action="store_true", help="never write")
    args = ap.parse_args()

    headers, body = fetch(DISCOVERY)
    revision = headers.get("x-pi-model-catalog-revision", "")
    if not REV_RE.match(revision):
        raise SystemExit(f"missing or malformed revision header: {revision!r}")

    digest = "sha256-" + hashlib.sha256(body).hexdigest()
    if digest != revision:
        raise SystemExit(f"body hash mismatch: header={revision} body={digest}")

    copilot = json.loads(body).get("github-copilot") or []
    if not any(m.get("type") == "classifier" for m in copilot):
        groups = sorted({f"{m.get('type')}/{m.get('api')}" for m in copilot})
        raise SystemExit(
            f"live catalog has no github-copilot classifier, "
            f"a source build would fail with TS2322. Groups: {groups}"
        )

    current = None
    if os.path.exists(PIN):
        with open(PIN, encoding="utf-8") as f:
            current = json.load(f).get("revision")

    print(f"live revision  : {revision}")
    print(f"pinned revision: {current}")
    print(f"catalog size   : {len(body)} bytes")

    if args.check:
        return 0 if current == revision else 1

    if current == revision and not args.force:
        print("unchanged, not writing")
        return 0

    os.makedirs(os.path.dirname(PIN), exist_ok=True)
    with open(PIN, "w", encoding="utf-8") as f:
        f.write(json.dumps({"revision": revision}, indent=2) + "\n")
    print(f"wrote {PIN}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
