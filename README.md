# Should I Buy It

A cooling-off period for purchases, and a running total of money not spent.

## Features

- Add things you want with a cooling-off period
- Buying unlocks only after the wait; skipping is always allowed
- Running totals of money not spent and money spent
- Decision history
- Responsive layout for phone and desktop, with automatic dark and light themes
- Current version shown beneath the application name
- In-app Changelog
- Local SQLite storage: no cloud services, no telemetry

## Requirements

- Linux host with Docker Engine and Docker Compose

## Install

```bash
git clone https://github.com/mx5matt/should-i-buy-it.git
cd should-i-buy-it
mkdir -p data
sudo chown 10001:10001 data
sudo chmod 750 data
printf 'APP_BIND=127.0.0.1\n' > .env
sudo docker compose up -d --build
```

Then open `http://127.0.0.1:8387`.

## Configuration

| Setting | Where | Default | Purpose |
|---|---|---|---|
| `APP_BIND` | `.env` | `127.0.0.1` | Host address the web port is published on |
| Port | `compose.yaml` | `8387` | Host port |

Set `APP_BIND` to your server's LAN address to reach it from other devices. Keep `.env` out of version control.

## Backup and restore

```bash
./scripts/backup.sh                                  # creates backups/app-YYYYMMDD-HHMMSS.sqlite3
./scripts/restore.sh backups/app-YYYYMMDD-HHMMSS.sqlite3
```

Backups are written to `backups/`, which is excluded from Git.

## Updating

```bash
./scripts/update.sh
```

This checks that the checkout is clean, makes a backup, pulls the latest release and rebuilds the container.

## Health check

`GET /health` returns `{"status": "ok", "version": "x.y.z"}`.

## Development

```bash
./scripts/run-tests.sh
```

Builds a test image and runs the full test suite inside it.

## Security

See [SECURITY.md](SECURITY.md). This version has no authentication and is intended for a trusted private network.

## Changelog

See [CHANGELOG.md](CHANGELOG.md), or the Changelog page inside the application.

## License

MIT. See [LICENSE](LICENSE).
