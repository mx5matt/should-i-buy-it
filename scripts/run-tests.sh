#!/usr/bin/env bash
# Build a test image and run the complete test suite inside it.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
IMAGE="${1:-should-i-buy-it:test}"

python3 -m py_compile app.py tests/*.py
sudo docker build --pull -t "$IMAGE" .
sudo docker run --rm --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=32m \
    --workdir /app --entrypoint python -e PYTHONPATH=/app \
    "$IMAGE" -m tests.test_app
