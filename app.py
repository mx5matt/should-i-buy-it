import math
import os
import sqlite3
from contextlib import contextmanager
from datetime import date, timedelta

from flask import Flask, abort, flash, jsonify, redirect, render_template, request, url_for

APP_VERSION = "0.1.1"
APP_TITLE = "Should I Buy It"
APP_INITIALS = "SB"
DB = os.environ.get("APP_DB", "/data/app.sqlite3")
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

app = Flask(__name__)
# Used only to sign flash messages. No accounts or sensitive sessions exist.
app.secret_key = os.environ.get("SECRET_KEY", "should-i-buy-it-local-flash-messages")


@contextmanager
def db():
    folder = os.path.dirname(DB)
    if folder:
        os.makedirs(folder, exist_ok=True)
    conn = sqlite3.connect(DB, timeout=30)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db():
    with db() as conn:
        conn.executescript(SCHEMA)


@app.before_request
def ensure_database():
    init_db()


@app.context_processor
def inject_metadata():
    return {"app_version": APP_VERSION, "app_title": APP_TITLE, "app_initials": APP_INITIALS}


def to_int(value):
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return None


def to_float(value):
    try:
        number = float(str(value).strip())
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None


def to_date(value):
    try:
        return date.fromisoformat(str(value).strip())
    except (TypeError, ValueError):
        return None


@app.get("/health")
def health():
    with db() as conn:
        conn.execute("SELECT 1").fetchone()
    return jsonify(status="ok", version=APP_VERSION)


def changelog_sections():
    try:
        with open(os.path.join(BASE_DIR, "CHANGELOG.md"), encoding="utf-8") as handle:
            content = handle.read()
    except OSError:
        return []
    sections, current = [], None
    for line in content.splitlines():
        if line.startswith("## "):
            current = {"title": line[3:].strip(), "groups": []}
            sections.append(current)
        elif line.startswith("### ") and current is not None:
            current["groups"].append({"title": line[4:].strip(), "items": []})
        elif line.startswith("- ") and current is not None:
            if not current["groups"]:
                current["groups"].append({"title": "Changes", "items": []})
            current["groups"][-1]["items"].append(line[2:].strip().replace("`", ""))
    return sections


@app.get("/changelog")
def changelog():
    return render_template("changelog.html", sections=changelog_sections())

SCHEMA = """
CREATE TABLE IF NOT EXISTS wishes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item TEXT NOT NULL,
    price REAL NOT NULL,
    added TEXT NOT NULL,
    wait_days INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'waiting' CHECK (status IN ('waiting', 'bought', 'skipped')),
    decided TEXT
);
"""


def describe(row, today):
    wish = dict(row)
    ready_on = date.fromisoformat(wish["added"]) + timedelta(days=wish["wait_days"])
    wish["ready_on"] = ready_on
    wish["remaining"] = max((ready_on - today).days, 0)
    wish["ready"] = today >= ready_on
    return wish


@app.get("/")
def index():
    today = date.today()
    with db() as conn:
        rows = conn.execute("SELECT * FROM wishes ORDER BY id DESC").fetchall()
    wishes = [describe(r, today) for r in rows]
    return render_template(
        "index.html",
        waiting=[w for w in wishes if w["status"] == "waiting"],
        decided=[w for w in wishes if w["status"] != "waiting"],
        saved=sum(w["price"] for w in wishes if w["status"] == "skipped"),
        spent=sum(w["price"] for w in wishes if w["status"] == "bought"),
    )


@app.post("/wishes")
def add_wish():
    item = request.form.get("item", "").strip()
    price = to_float(request.form.get("price"))
    wait_days = to_int(request.form.get("wait_days", "7"))
    if not item or len(item) > 120 or price is None or not 0 <= price <= 10_000_000 or wait_days is None or not 0 <= wait_days <= 365:
        flash("Enter an item, a price of 0 or more, and a waiting period of 0 to 365 days.")
        return redirect(dashboard_return(url_for("index")))
    with db() as conn:
        conn.execute("INSERT INTO wishes(item, price, added, wait_days) VALUES (?, ?, ?, ?)",
                     (item, round(price, 2), date.today().isoformat(), wait_days))
    return redirect(dashboard_return(url_for("index")))


@app.post("/wishes/<int:wish_id>/decide")
def decide(wish_id):
    status = request.form.get("status", "")
    if status not in ("bought", "skipped"):
        abort(400)
    with db() as conn:
        row = conn.execute("SELECT * FROM wishes WHERE id = ?", (wish_id,)).fetchone()
        if row is None:
            abort(404)
        wish = describe(row, date.today())
        if wish["status"] != "waiting":
            flash("That decision has already been made.")
        elif status == "bought" and not wish["ready"]:
            flash(f"Still cooling off: {wish['remaining']} day(s) left before buying.")
        else:
            conn.execute("UPDATE wishes SET status = ?, decided = ? WHERE id = ?", (status, date.today().isoformat(), wish_id))
    return redirect(dashboard_return(url_for("index")))


@app.post("/wishes/<int:wish_id>/delete")
def delete_wish(wish_id):
    with db() as conn:
        conn.execute("DELETE FROM wishes WHERE id = ?", (wish_id,))
    return redirect(dashboard_return(url_for("index")))


if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=8080)

# Safe same-application return target. External, protocol-relative and control-character URLs are rejected.
def dashboard_return(default='/'):
    from urllib.parse import urlsplit
    target = request.form.get('return_to', '')
    if not target or not target.startswith('/') or target.startswith('//') or '\\' in target:
        return default
    if any(ord(c) < 32 or ord(c) == 127 for c in target):
        return default
    parsed = urlsplit(target)
    if parsed.scheme or parsed.netloc or parsed.fragment or parsed.path != '/':
        return default
    return target
