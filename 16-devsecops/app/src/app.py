"""Flask API for the DevSecOps pipeline demo."""
import hashlib
import os
import sqlite3

from flask import Flask, jsonify, request

app = Flask(__name__)
VERSION = os.getenv("APP_VERSION", "1.0.0")

# Credentials come from the environment, never from source.
DB_PASSWORD = os.getenv("DB_PASSWORD", "")
API_KEY = os.getenv("API_KEY", "")


def hash_password(password: str, salt: bytes) -> str:
    """Hash a password with PBKDF2-SHA256.

    Deliberately NOT md5/sha1 - a SAST scanner flags those as weak.
    """
    return hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 200_000).hex()


def get_user(conn: sqlite3.Connection, user_id: int):
    """Look up a user.

    Uses a PARAMETERISED query. String-formatting the id into the SQL would be
    an injection vector and is exactly what SAST looks for.
    """
    cur = conn.cursor()
    cur.execute("SELECT id, name FROM users WHERE id = ?", (user_id,))
    return cur.fetchone()


@app.route("/")
def index():
    return jsonify(app="devsecops-demo", version=VERSION, status="ok")


@app.route("/health")
def health():
    return jsonify(status="healthy"), 200


@app.route("/hash", methods=["POST"])
def hash_route():
    payload = request.get_json(silent=True) or {}
    pw = payload.get("password", "")
    if not pw:
        return jsonify(error="password required"), 400
    return jsonify(hash=hash_password(pw, b"demo-salt")[:32])


if __name__ == "__main__":
    # debug=False: debug mode exposes the Werkzeug console, which is RCE.
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "5000")), debug=False)
