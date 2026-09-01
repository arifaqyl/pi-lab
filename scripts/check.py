#!/usr/bin/env python3
"""Hit every endpoint from another machine and print OK/ERR. Stdlib only.

    python check.py                  # uses the list below
    python check.py https://example.com/ https://example.com/traffic/api/health
"""
from __future__ import annotations

import sys
import urllib.request

# (label, url). Edit for your lab. Public URLs test the tunnel end to end;
# LAN URLs test the box itself.
SERVICES: list[tuple[str, str]] = [
    ("portfolio",        "https://arifaqyl.me/"),
    ("trafficmy api",    "https://arifaqyl.me/traffic/api/health/live"),
    ("trafficmy ui",     "https://arifaqyl.me/traffic/"),
    ("sah.bukti",        "https://arifaqyl.me/sahbukti/"),
    ("ops console",      "https://arifaqyl.me/ops-console/"),
]


def check(label: str, url: str, timeout: int = 8) -> bool:
    req = urllib.request.Request(url, headers={"User-Agent": "pi-lab-check/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            print(f"  OK   {label:<16} {r.status}  {url}")
            return True
    except Exception as exc:  # noqa: BLE001 - we want the reason, whatever it is
        print(f"  ERR  {label:<16} {exc}  {url}")
        return False


def main(argv: list[str]) -> int:
    targets = [(u, u) for u in argv] if argv else SERVICES
    results = [check(label, url) for label, url in targets]
    print(f"\n{sum(results)}/{len(results)} up")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
