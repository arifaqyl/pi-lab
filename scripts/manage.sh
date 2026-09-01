#!/usr/bin/env bash
# One place for the four things you actually do to a homelab.
#   ./manage.sh status | restart | backup | logs [app]
set -euo pipefail

HOME_DIR="${HOME_DIR:-$HOME}"
BACKUP_ROOT="${BACKUP_ROOT:-$HOME_DIR/backups}"
# Every SQLite file worth keeping. Add yours.
DB_FILES=(
  "$HOME_DIR/aduanmy/data/aduanmy.db"
  "$HOME_DIR/kedai-ops/data/sah_bukti.db"
  "$HOME_DIR/student-bot/messages.db"
)
SESSION_DIRS=(
  "$HOME_DIR/waha_sessions"
)

G="\033[0;32m"; Y="\033[1;33m"; B="\033[0;34m"; N="\033[0m"

case "${1:-}" in
  status)
    echo -e "${G}>>> system${N}"
    echo "uptime: $(uptime -p)"
    echo "ram:    $(free -h | awk '/Mem:/ {print $3 " / " $2}')"
    echo "disk:   $(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 " used)"}')"
    echo "temp:   $(vcgencmd measure_temp 2>/dev/null || echo n/a)"
    echo -e "\n${G}>>> pm2${N}";    pm2 list
    echo -e "\n${G}>>> docker${N}"; docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
    echo -e "\n${G}>>> nginx${N}";  systemctl is-active nginx
    ;;
  restart)
    echo -e "${Y}>>> restarting pm2 apps${N}";   pm2 restart all
    echo -e "${Y}>>> restarting containers${N}"; docker ps -q | xargs -r docker restart
    ;;
  backup)
    dest="$BACKUP_ROOT/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$dest"
    for f in "${DB_FILES[@]}";    do [ -f "$f" ] && cp -p "$f" "$dest/"; done
    for d in "${SESSION_DIRS[@]}"; do [ -d "$d" ] && tar -czf "$dest/$(basename "$d").tar.gz" -C "$(dirname "$d")" "$(basename "$d")"; done
    echo -e "${G}backup written to $dest${N}"; ls -lh "$dest"
    ;;
  logs)
    pm2 logs "${2:-}"
    ;;
  *)
    echo "usage: $0 {status|restart|backup|logs [app]}"; exit 1
    ;;
esac
