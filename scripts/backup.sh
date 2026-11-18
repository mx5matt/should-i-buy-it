#!/usr/bin/env bash
# Create a consistent SQLite backup in backups/.
set -Eeuo pipefail
cd "$(dirname "$0")/.."

CONTAINER="should-i-buy-it"
stamp="$(date +%Y%m%d-%H%M%S)"
out="backups/app-${stamp}.sqlite3"

sudo mkdir -p backups
sudo chmod 700 backups

if ! sudo test -f data/app.sqlite3; then
    echo "No database exists yet; nothing to back up."
    exit 0
fi

if [[ "$(sudo docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)" == "true" ]]; then
    # Use SQLite's online backup API inside the running container.
    sudo docker exec "$CONTAINER" python -c "import sqlite3; s=sqlite3.connect('/data/app.sqlite3'); d=sqlite3.connect('/data/.backup-in-progress.sqlite3'); s.backup(d); d.close(); s.close()"
    sudo mv data/.backup-in-progress.sqlite3 "$out"
else
    sudo cp -a data/app.sqlite3 "$out"
fi

sudo chmod 600 "$out"
sudo sh -c "cd backups && sha256sum '$(basename "$out")' > '$(basename "$out").sha256'"
echo "Backup created: $out"
