#!/usr/bin/env python3
"""External uptime check for the Pi homelab, run by GitHub Actions every 10 minutes.

It runs off the Pi on purpose: when the Pi loses power, nothing on it can raise
an alarm. Telegram gets a message only when a service goes down or comes back,
plus a reminder every 6 hours while something stays down.

State lives in status/uptime.json, committed only when it changes (and at least
monthly, which also keeps GitHub from pausing the schedule on a quiet repo).
"""
from __future__ import annotations

import json
import os
import pathlib
import time
import urllib.error
import urllib.parse
import urllib.request

# name: (url, status codes that count as up). 401 = up behind a login.
CHECKS = {
    "portfolio": ("https://arifaqyl.me/", {200}),
    "trafficmy": ("https://arifaqyl.me/traffic/", {200}),
    "sahbukti": ("https://arifaqyl.me/sahbukti/", {200}),
    "ops-console": ("https://arifaqyl.me/ops-console/", {200, 401}),
    "fb-hunter": ("https://arifaqyl.me/hunter/", {200, 401}),
    "n8n": ("https://n8n.arifaqyl.me/", {200}),
}
STATE = pathlib.Path("status/uptime.json")
REMIND_EVERY = 6 * 3600
KEEPALIVE = 30 * 86400


def get_status(url: str) -> int:
    req = urllib.request.Request(url, headers={"User-Agent": "pi-lab-uptime/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return 0  # timeout, DNS, TLS


def probe() -> dict:
    res = {}
    for name, (url, ok) in CHECKS.items():
        code = get_status(url)
        if code not in ok:
            time.sleep(15)  # one retry so a short blip does not page
            code = get_status(url)
        res[name] = {"up": code in ok, "code": code}
    return res


def ago(seconds: int) -> str:
    h, m = divmod(seconds // 60, 60)
    return f"{h // 24}d {h % 24}h" if h >= 24 else f"{h}h {m}m" if h else f"{m}m"


def send(text: str) -> bool:
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    chat = os.environ.get("TELEGRAM_CHAT_ID")
    if not token or not chat:
        print("telegram not configured")
        return False
    data = urllib.parse.urlencode({"chat_id": chat, "text": text}).encode()
    try:
        urllib.request.urlopen(f"https://api.telegram.org/bot{token}/sendMessage", data, timeout=20)
        return True
    except Exception as exc:
        print(f"telegram send failed: {exc}")
        return False


def describe_down(down: list[str], res: dict) -> str:
    codes = ", ".join(f"{n} ({res[n]['code'] or 'no answer'})" for n in down)
    if len(down) == len(CHECKS):
        # 530 / 1033 from Cloudflare = tunnel cannot reach the Pi
        return f"arifaqyl.me is unreachable. Pi, power, WiFi or the tunnel is down.\n{codes}"
    return f"Down: {codes}"


def main() -> int:
    now = int(time.time())
    old = json.loads(STATE.read_text()) if STATE.exists() else {}
    prev = old.get("services", {})
    res = probe()

    for name, r in res.items():
        p = prev.get(name)
        r["since"] = p["since"] if p and p["up"] == r["up"] else now

    down = [n for n, r in res.items() if not r["up"]]
    went_down = [n for n in down if prev.get(n, {}).get("up", True)]
    came_up = [n for n, r in res.items() if r["up"] and n in prev and not prev[n]["up"]]
    last_alert = old.get("last_alert", 0)

    msgs = []
    if went_down:
        msgs.append(describe_down(down, res))
    elif down and now - last_alert >= REMIND_EVERY:
        oldest = min(res[n]["since"] for n in down)
        msgs.append(f"Still down after {ago(now - oldest)}. " + describe_down(down, res))
    if came_up:
        back = ", ".join(f"{n} (down {ago(now - prev[n]['since'])})" for n in came_up)
        msgs.append(f"Back up: {back}")
    if os.environ.get("TEST_ALERT") == "true":
        status = "all up" if not down else f"{len(down)} down"
        msgs.append(f"Test from pi-lab uptime check: {len(CHECKS)} endpoints checked, {status}.")

    if msgs and send("\n\n".join(msgs)):
        last_alert = now

    print(json.dumps(res, indent=2))
    changed = bool(went_down or came_up) or last_alert != old.get("last_alert", 0)
    stale = now - old.get("written", 0) >= KEEPALIVE
    if changed or stale or not STATE.exists():
        STATE.parent.mkdir(exist_ok=True)
        STATE.write_text(json.dumps(
            {"written": now, "last_alert": last_alert, "services": res}, indent=2) + "\n")
        out = os.environ.get("GITHUB_OUTPUT")
        if out:
            with open(out, "a") as f:
                f.write("commit=true\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
