"""Shared test setup. Uses a throwaway SQLite file; all data is synthetic."""
import os
import sqlite3
import tempfile

_handle = tempfile.NamedTemporaryFile(prefix="app-test-", suffix=".sqlite3", delete=False)
_handle.close()
DB_PATH = _handle.name
os.environ["APP_DB"] = DB_PATH

from app import APP_VERSION, app  # noqa: E402

app.config["TESTING"] = True
client = app.test_client()


def query(sql, params=()):
    conn = sqlite3.connect(DB_PATH)
    try:
        return conn.execute(sql, params).fetchall()
    finally:
        conn.close()


def check_common():
    response = client.get("/health")
    assert response.status_code == 200, response.status_code
    assert response.get_json() == {"status": "ok", "version": APP_VERSION}

    response = client.get("/")
    assert response.status_code == 200, response.status_code
    assert ("<small>v" + APP_VERSION + "</small>").encode() in response.data, "version missing under app name"
    assert b'href="/changelog"' in response.data, "Changelog link missing"

    response = client.get("/changelog")
    assert response.status_code == 200, response.status_code
    assert ("[" + APP_VERSION + "]").encode() in response.data, "current version missing from Changelog"

    assert client.get("/no-such-page").status_code == 404


def cleanup():
    os.unlink(DB_PATH)
