# pi-lab

Four production apps on a Raspberry Pi 4, reachable worldwide over HTTPS,
with **zero open ports on the router**. This is the actual runbook for
[arifaqyl.me](https://arifaqyl.me) — not a tutorial written from memory, but
the config that is running as you read this, with secrets stripped.

```
internet ──HTTPS──▶ Cloudflare edge ──tunnel (outbound only)──▶ Pi
                                                                │
                                          nginx :80 ────────────┤
                                            /            static portfolio
                                            /traffic/    FastAPI  :8002   (PM2)
                                            /sahbukti/   FastAPI  :8000   (PM2)
                                            /ops-console/ Python  :8091   (PM2)
                                            /waha/       Docker   :2785
                                          n8n.arifaqyl.me ─▶ Docker :5678
```

## Why this shape

**No inbound ports.** `cloudflared` opens an outbound connection to
Cloudflare and traffic comes back down it. The router has nothing
forwarded. Port scans of the home IP find nothing. TLS terminates at the
edge, so nginx on the Pi speaks plain HTTP on the loopback interface only.

**One nginx, path-routed.** Every app lives under a path on one hostname.
No wildcard DNS, no per-app certificates, and adding an app is one
`location` block. Apps must be told their prefix (see the env vars in the
PM2 config) so they generate correct links.

**PM2 for Python, Docker for things that ship as images.** PM2 gives each
Python service a restart policy, log rotation, and one `ecosystem.config.js`
that is the whole inventory of what runs. Docker is used only for WAHA and
n8n, which are distributed as images.

**SQLite everywhere.** Every app is a single SQLite file. Backups are a
`cp`. Restores are a `cp`. There is no database server to keep alive.

## The files

| File | What it is |
|---|---|
| `templates/cloudflared.yml` | Tunnel ingress: hostname → local service, catch-all 404 |
| `templates/nginx.conf` | Path-routed reverse proxy with the headers FastAPI needs |
| `templates/ecosystem.config.js` | PM2 inventory: name, cwd, venv interpreter, env per app |
| `scripts/manage.sh` | `status` / `restart` / `backup` / `logs` in one place |
| `scripts/check.py` | Hits every endpoint from another machine; prints OK/ERR |
| `scripts/stats.cron` | Example cron that regenerates a static file into the web root |

## Setting it up

```
# on the Pi
sudo apt install nginx docker.io
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt install nodejs
sudo npm i -g pm2 pm2-logrotate

# cloudflared: install, login, create a tunnel, route DNS
cloudflared tunnel login
cloudflared tunnel create homelab
cloudflared tunnel route dns homelab example.com
sudo cp templates/cloudflared.yml /etc/cloudflared/config.yml   # edit tunnel id + hostnames
sudo cloudflared service install

# nginx + apps
sudo cp templates/nginx.conf /etc/nginx/sites-enabled/default    # edit paths + ports
cp templates/ecosystem.config.js ~/ecosystem.config.js            # edit apps
pm2 start ~/ecosystem.config.js && pm2 save && pm2 startup
```

## Operating it

```
./manage.sh status      # uptime, RAM, disk, SoC temperature, PM2 table, containers, nginx
./manage.sh backup      # timestamped copy of every SQLite file + WAHA sessions
./manage.sh logs trafficmy-api
python check.py         # from your laptop: is everything answering?
```

## Things learned the hard way

- **Playwright on ARM needs system libraries** that `pip install` does not
  bring. A collector that launches Chromium will fail with a wall of text
  until `playwright install-deps chromium` has run as root. One of mine was
  failing every 15 minutes for a month before anyone read the error.
- **Silent failure is the enemy.** A scraper that returns zero rows and no
  exception looks exactly like a quiet day. Page yourself on *transitions*
  (healthy → empty for N runs, and back), never on every run, or you will
  mute the bot within a week. See `check_source_health_and_alert()` in
  [aduanmy](https://github.com/arifaqyl/aduanmy) for the pattern.
- **Cache-bust static assets by content hash.** Cloudflare caches images
  for hours. Replacing `hero.png` with a new file of the same name means
  visitors see the old one until the cache expires. `hero.3fa1b2c4.png`
  never has that problem.
- **`/var/www` is `www-data`'s.** Deploy by copying to `/tmp` and
  `sudo install -o www-data -g www-data`, not by `chmod 777`.
- **A 4 GB Pi runs all of this at ~1.5 GB RAM.** The 8 GB model is
  comfortable. The SD card is the part that will fail; keep backups off it.

## What it costs

Cloudflare Tunnel is free. The domain is ~RM50 a year. Electricity for a Pi
4 under this load is a few ringgit a month. The former DigitalOcean droplet
this replaced was paid for by a student credit that ran out — which is the
whole reason this exists.

## Licence

MIT. Templates are examples; edit them.
