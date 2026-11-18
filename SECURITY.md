# Security

Should I Buy It is designed to be self-hosted on a trusted private network.

Version 0.1.0 does not include user accounts or authentication. Do not expose it directly to the public internet. If remote access is needed, place it behind a VPN or an authenticated HTTPS reverse proxy.

## Data

- Application data is stored in `data/app.sqlite3`.
- Never commit `.env`, databases, backups or credentials.
- The container runs as an unprivileged user (UID 10001).

## Reporting a vulnerability

Please report security issues privately to the repository owner rather than opening a public issue containing exploit details.
