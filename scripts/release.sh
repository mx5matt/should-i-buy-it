#!/usr/bin/env bash
# Repeatable release: candidate build, full tests, privacy scan, backup,
# commit, annotated tag, push, deploy the exact tested image, verify.
set -Eeuo pipefail

SLUG="should-i-buy-it"
TITLE="Should I Buy It"
PORT="8387"
REPO_URL="https://github.com/mx5matt/should-i-buy-it.git"
GIT_NAME="Matt Lemmon"
GIT_EMAIL="mx5matt@users.noreply.github.com"

cd "$(dirname "$0")/.."

STAGE="pre-flight"
PUBLISHED="no"
fail() { echo; echo "STOP during ${STAGE}: $*" >&2; report; exit 1; }
report() {
    if [[ "$PUBLISHED" == "yes" ]]; then
        echo "Git has ALREADY been published. Do not rewrite history. Diagnose, then release a new PATCH version if source changes are needed." >&2
    else
        echo "Nothing was published to GitHub." >&2
    fi
}
trap 'rc=$?; echo; echo "RELEASE FAILED during: ${STAGE} (exit ${rc})" >&2; report; exit "$rc"' ERR
step() { STAGE="$1"; echo; echo "=== $1 ==="; }

[[ -f .env ]] || fail ".env is missing (it must define APP_BIND)."
set -a; . ./.env; set +a
BIND="${APP_BIND:-127.0.0.1}"
URL="http://${BIND}:${PORT}"

VERSION="$(sed -n 's/^APP_VERSION = "\(.*\)"$/\1/p' app.py)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "APP_VERSION in app.py is missing or not MAJOR.MINOR.PATCH."
TAG="v${VERSION}"
CANDIDATE="${SLUG}:${VERSION}-candidate"
RELEASE_IMAGE="${SLUG}:${VERSION}"

echo "Releasing ${TITLE} ${TAG}"

step "Pre-flight"
[[ "$(git branch --show-current)" == "main" ]] || fail "Not on branch main."
[[ "$(git remote get-url origin)" == "$REPO_URL" ]] || fail "origin is not ${REPO_URL}."
[[ "$(git config user.name)" == "$GIT_NAME" ]] || fail "Git user.name is not ${GIT_NAME}."
[[ "$(git config user.email)" == "$GIT_EMAIL" ]] || fail "Git user.email is not the GitHub no-reply address."
if [[ -n "$(git ls-remote --heads origin)" ]]; then
    git fetch origin --tags
    git merge-base --is-ancestor origin/main HEAD || fail "Local main is behind or diverged from origin/main."
fi
git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null && fail "Tag ${TAG} already exists locally."
[[ -z "$(git ls-remote --tags origin "refs/tags/${TAG}")" ]] || fail "Tag ${TAG} already exists on GitHub."
grep -q "^    image: ${RELEASE_IMAGE}$" compose.yaml || fail "compose.yaml image is not ${RELEASE_IMAGE}."
grep -q "^## \[${VERSION}\] - [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}$" CHANGELOG.md || fail "CHANGELOG.md has no dated entry for ${VERSION}."
echo "Version ${VERSION}: app.py, compose.yaml and CHANGELOG.md agree."

step "Validate source"
python3 -m py_compile app.py tests/*.py
for f in scripts/*.sh; do bash -n "$f"; done
git diff --check
find . -path ./data -prune -o -path ./backups -prune -o -path ./.git -prune \
     -o -type d -name __pycache__ -print0 | xargs -0 -r rm -rf

step "Build candidate ${CANDIDATE}"
sudo docker build --pull --no-cache -t "$CANDIDATE" .

step "Run complete test suite inside candidate"
sudo docker run --rm --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=32m \
    --workdir /app --entrypoint python -e PYTHONPATH=/app \
    "$CANDIDATE" -m tests.test_app
CANDIDATE_VERSION="$(sudo docker run --rm --workdir /app --entrypoint python "$CANDIDATE" -c 'from app import APP_VERSION; print(APP_VERSION)')"
[[ "$CANDIDATE_VERSION" == "$VERSION" ]] || fail "Candidate reports ${CANDIDATE_VERSION}, expected ${VERSION}."

step "Privacy and secret scan"
PATTERN='(^|[^0-9])(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3})|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(password|passwd|api[_-]?key|access[_-]?token)[[:space:]]*[:=][[:space:]]*[^[:space:]]{6,}'
EMAIL='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
ALLOWED_EMAIL='@users\.noreply\.github\.com|@example\.(com|net|org)'
scan="$(mktemp)"
while IFS= read -r -d '' f; do
    case "$f" in data/*|backups/*|.env|*.db|*.sqlite|*.sqlite3|*.pyc) continue ;; esac
    [[ -f "$f" ]] || continue
    grep -HInE "$PATTERN" "$f" >>"$scan" || true
    grep -HInoE "$EMAIL" "$f" | grep -vE "$ALLOWED_EMAIL" >>"$scan" || true
    if [[ "$BIND" != "127.0.0.1" ]]; then grep -HInF "$BIND" "$f" >>"$scan" || true; fi
done < <(git ls-files --cached --others --exclude-standard -z)
if [[ -s "$scan" ]]; then
    echo "Potential private material found (content redacted):"
    sed -E 's/^([^:]+:[0-9]+):.*/\1: [REDACTED]/' "$scan" | sort -u
    rm -f "$scan"
    fail "Privacy scan failed. Fix the source; do not weaken the scan."
fi
rm -f "$scan"
echo "Privacy scan passed."

step "Back up production data"
sudo mkdir -p data
sudo chown 10001:10001 data
sudo chmod 750 data
./scripts/backup.sh

step "Stage intended release files only"
git add -- README.md CHANGELOG.md LICENSE SECURITY.md .gitignore .dockerignore \
    Dockerfile compose.yaml requirements.txt app.py templates static tests scripts
git diff --cached --check
if git diff --cached --name-only | grep -E '(^|/)\.env$|^data/|^backups/|\.(db|sqlite|sqlite3)$'; then
    fail "A forbidden file is staged."
fi
[[ -n "$(git diff --cached --name-only)" ]] || fail "Nothing is staged."
leftover="$(git status --porcelain | grep -vE '^[MADR]  ' || true)"
[[ -z "$leftover" ]] || { echo "$leftover"; fail "Unstaged or unexpected files remain."; }
echo "Files in this release:"
git diff --cached --name-status
git diff --cached --stat | tail -n 1

step "Commit and annotated tag"
git commit -q -m "Release ${TITLE} ${TAG}"
git tag -a "$TAG" -m "${TITLE} ${TAG}"
git log -1 --oneline

step "Push main"
git push -u origin main
PUBLISHED="yes"

step "Push tag ${TAG}"
git push origin "$TAG"

step "Promote the exact tested candidate"
sudo docker tag "$CANDIDATE" "$RELEASE_IMAGE"
[[ "$(sudo docker image inspect -f '{{.Id}}' "$CANDIDATE")" == "$(sudo docker image inspect -f '{{.Id}}' "$RELEASE_IMAGE")" ]] \
    || fail "Release image does not match the tested candidate."

step "Deploy without rebuilding"
sudo docker compose up -d --no-build

step "Post-deployment verification"
health=""
for _ in $(seq 1 45); do
    health="$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$SLUG" 2>/dev/null || true)"
    [[ "$health" == "healthy" ]] && break
    sleep 2
done
if [[ "$health" != "healthy" ]]; then
    sudo docker compose logs --tail=80
    fail "Container is not healthy (state: ${health:-unknown})."
fi

running_image="$(sudo docker inspect -f '{{.Config.Image}}' "$SLUG")"
[[ "$running_image" == "$RELEASE_IMAGE" ]] || fail "Running image is ${running_image}."

binding="$(sudo docker port "$SLUG" 8080/tcp | head -n 1)"
[[ "$binding" == "${BIND}:${PORT}" ]] || fail "Port binding is ${binding}, expected ${BIND}:${PORT}."

running_version="$(curl -fsS "${URL}/health" | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')"
[[ "$running_version" == "$VERSION" ]] || fail "Running version is ${running_version}."

[[ "$(curl -sS -o /dev/null -w '%{http_code}' "${URL}/")" == "200" ]] || fail "Home page did not return 200."
[[ "$(curl -sS -o /dev/null -w '%{http_code}' "${URL}/changelog")" == "200" ]] || fail "Changelog did not return 200."
curl -fsS "${URL}/" | grep -q "v${VERSION}" || fail "Home page does not show v${VERSION}."
curl -fsS "${URL}/changelog" | grep -q "\[${VERSION}\]" || fail "Changelog does not show ${VERSION}."

integrity="$(sudo docker exec "$SLUG" python -c "import sqlite3; c=sqlite3.connect('/data/app.sqlite3'); print(c.execute('PRAGMA integrity_check').fetchone()[0])")"
[[ "$integrity" == "ok" ]] || fail "SQLite integrity check returned: ${integrity}."

[[ -z "$(git status --porcelain)" ]] || fail "Working tree is not clean after release."
[[ "$(git describe --tags --exact-match)" == "$TAG" ]] || fail "HEAD is not tagged ${TAG}."
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "origin/main does not match HEAD."

echo
echo "========================================"
echo " ${TITLE} ${TAG} RELEASE COMPLETE"
echo "========================================"
echo "Commit:    $(git rev-parse --short HEAD)"
echo "Image:     ${running_image}"
echo "Version:   ${running_version}"
echo "Container: ${health}"
echo "Binding:   ${binding}"
echo "SQLite:    ${integrity}"
