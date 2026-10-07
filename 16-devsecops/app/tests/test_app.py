import sqlite3

from src.app import app, get_user, hash_password


def test_hash_is_deterministic():
    a = hash_password("hunter2", b"salt")
    b = hash_password("hunter2", b"salt")
    assert a == b and len(a) == 64


def test_hash_differs_by_salt():
    assert hash_password("hunter2", b"s1") != hash_password("hunter2", b"s2")


def test_get_user_parameterised():
    conn = sqlite3.connect(":memory:")
    conn.execute("CREATE TABLE users (id INTEGER, name TEXT)")
    conn.execute("INSERT INTO users VALUES (1, 'saswata')")
    assert get_user(conn, 1) == (1, "saswata")


def test_get_user_resists_injection():
    """A parameterised query binds the input as a VALUE, never as SQL."""
    conn = sqlite3.connect(":memory:")
    conn.execute("CREATE TABLE users (id INTEGER, name TEXT)")
    conn.execute("INSERT INTO users VALUES (1, 'saswata')")

    # With string formatting, "1 OR 1=1" would match every row. Bound as a
    # parameter it is just a meaningless id, so the query returns nothing...
    assert get_user(conn, "1 OR 1=1") is None  # type: ignore[arg-type]

    # ...and the classic drop-table payload leaves the table intact.
    assert get_user(conn, "1; DROP TABLE users") is None  # type: ignore[arg-type]
    assert conn.execute("SELECT COUNT(*) FROM users").fetchone()[0] == 1


def test_index():
    assert app.test_client().get("/").status_code == 200


def test_health():
    assert app.test_client().get("/health").status_code == 200


def test_hash_route_requires_password():
    assert app.test_client().post("/hash", json={}).status_code == 400


def test_hash_route_ok():
    r = app.test_client().post("/hash", json={"password": "hunter2"})
    assert r.status_code == 200 and len(r.get_json()["hash"]) == 32
