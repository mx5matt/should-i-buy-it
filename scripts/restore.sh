#!/usr/bin/env bash
# Restore a backup created by scripts/backup.sh.
set -Eeuo pipefail
[[ $# -eq 1 ]] || { echo "Usage: $0 BACKUP_FILE" >&2; exit 2; }

cd "$(dirname "$0")/.."
CONTAINER="should-i-buy-it"
backup="$1"

sudo test -f "$backup" || { echo "Backup not found: $backup" >&2; exit 1; }

if sudo test -f "${backup}.sha256"; then
    sudo sh -c "cd '$(dirname "$backup")' && sha256sum -c '$(basename "$backup").sha256'"
fi

sudo docker compose down

if sudo test -f data/app.sqlite3; then
    sudo cp -a data/app.sqlite3 "data/app.sqlite3.before-restore-$(date +%Y%m%d-%H%M%S)"
fi

sudo cp "$backup" data/app.sqlite3
sudo chown 10001:10001 data/app.sqlite3
sudo chmod 600 data/app.sqlite3

sudo docker compose up -d --no-build

for _ in $(seq 1 30); do
    state="$(sudo docker inspect -f '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || true)"
    [[ "$state" == "healthy" ]] && { echo "Restore complete; container healthy."; exit 0; }
    sleep 2
done
echo "Container did not become healthy after restore." >&2
exit 1
