#!/usr/bin/env bash
# Update an installation to the latest published release.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
CONTAINER="should-i-buy-it"

[[ -z "$(git status --porcelain)" ]] || { echo "Working tree has local changes; aborting." >&2; exit 1; }

./scripts/backup.sh
git pull --ff-only
sudo docker compose up -d --build

for _ in $(seq 1 30); do
    state="$(sudo docker inspect -f '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || true)"
    [[ "$state" == "healthy" ]] && { echo "Update complete; container healthy."; exit 0; }
    sleep 2
done
echo "Container did not become healthy after update." >&2
exit 1
