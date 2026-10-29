#!/bin/bash
# Nightly Pi backup: app databases, n8n Postgres, WhatsApp session, configs.
# Installed at /usr/local/sbin/pi-backup, run as root by /etc/cron.d/pi-backup.
# Output: /home/aqyl/backups/nightly/pi-YYYYMMDD.tar.zst, last 14 kept.
# The Windows PC pulls these every day (see pull_backups.ps1), so a copy lives off the Pi.
set -uo pipefail

HOME_DIR=/home/aqyl
OUT=$HOME_DIR/backups/nightly
KEEP_DAYS=14
STAMP=$(date +%Y%m%d)
FILE=$OUT/pi-$STAMP.tar.zst
WORK=$(mktemp -d /tmp/pi-backup.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

# telegram creds are reused from fb-hunter's .env
alert() {
  local env=$HOME_DIR/fb-hunter/.env token chat
  token=$(grep -E '^TELEGRAM_BOT_TOKEN=' "$env" | cut -d= -f2- | tr -d '"'"'")
  chat=$(grep -E '^TELEGRAM_CHAT_ID=' "$env" | cut -d= -f2- | tr -d '"'"'")
  [ -n "$token" ] && [ -n "$chat" ] || return 0
  curl -s -m 20 "https://api.telegram.org/bot$token/sendMessage" \
    --data-urlencode "chat_id=$chat" --data-urlencode "text=$1" >/dev/null || true
}
fail() { echo "FAILED: $1"; alert "Pi backup failed: $1"; exit 1; }

mkdir -p "$OUT" "$WORK/db"
chown aqyl:aqyl "$HOME_DIR/backups" "$OUT"
chmod 700 "$OUT"

# 1. sqlite: use the backup API so a live database is copied consistently
python3 - "$WORK/db" <<'PY' || fail "sqlite copy"
import pathlib, sqlite3, sys
dst = pathlib.Path(sys.argv[1])
dbs = [
    "student-bot/messages.db",
    "student-bot/deadlines.db",
    "aduanmy/data/aduanmy.db",
    "fb-hunter/data/hunter.db",
    "flight-tracker/flight_history.db",
    "kedai-ops/data/kedai_ops.sqlite3",
    "waha_sessions/webjs/waha.sqlite3",
]
for rel in dbs:
    src = pathlib.Path("/home/aqyl") / rel
    if not src.exists() or src.stat().st_size == 0:
        print("skip", rel)
        continue
    s = sqlite3.connect(src, timeout=30)
    d = sqlite3.connect(dst / rel.replace("/", "__"))
    s.backup(d)
    d.close()
    s.close()
    print("ok", rel)
PY

# 2. n8n postgres
docker exec n8n-social-postgres-1 pg_dump -U n8n -d n8n -Fc > "$WORK/n8n.pgdump" \
  || fail "pg_dump n8n"

# 3. small state that is not files on disk
crontab -u aqyl -l > "$WORK/crontab-aqyl.txt" 2>/dev/null || true
cp "$HOME_DIR/.pm2/dump.pm2" "$WORK/" 2>/dev/null || true

# 4. one archive: work dir + configs + secrets (.env, tunnel creds), so keep it private
tar --zstd -cf "$FILE.tmp" --ignore-failed-read \
  --exclude='n8n-social/data/browser-profiles' \
  -C "$WORK" . \
  -C / \
  home/aqyl/ecosystem.config.js home/aqyl/manage.sh home/aqyl/tools \
  home/aqyl/fb-hunter/.env home/aqyl/flight-tracker/.env home/aqyl/n8n-social \
  home/aqyl/waha_sessions home/aqyl/.cloudflared \
  etc/cloudflared etc/nginx/sites-enabled etc/cron.d etc/ssh/sshd_config.d etc/smartd.conf \
  etc/systemd/system etc/playit opt/AdGuardHome/AdGuardHome.yaml 2>"$WORK/tar.err"
rc=$?
# tar exit 1 = a file changed while being read, which is expected for live dirs
[ $rc -le 1 ] || { cat "$WORK/tar.err"; fail "tar exit $rc"; }

zstd -q -t "$FILE.tmp" || fail "archive did not verify"
size=$(stat -c %s "$FILE.tmp")
[ "$size" -gt 1000000 ] || fail "archive too small ($size bytes)"
mv "$FILE.tmp" "$FILE"
chown aqyl:aqyl "$FILE"
chmod 600 "$FILE"

find "$OUT" -name 'pi-*.tar.zst' -mtime +$KEEP_DAYS -delete
echo "$(basename "$FILE") $size $(date -Iseconds)" > "$OUT/latest.txt"
chown aqyl:aqyl "$OUT/latest.txt"
echo "OK $FILE $size bytes"
