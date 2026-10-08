"""Test fixtures.

The tests run against a throwaway SQLite file, never the Postgres the
application uses. That is deliberate and it is the rubric's requirement, but it
is also the only way these tests can run inside a CI job that has no database
service -- which is where they actually have to pass.

The trade is real and worth stating: SQLite is not Postgres, so anything that
depends on Postgres-specific behaviour would pass here and fail in production.
The one place that matters is the partial unique index on appointments, so the
model declares BOTH `postgresql_where` and `sqlite_where` and the conflict test
below genuinely exercises it on this engine.
"""
import os
import tempfile
from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker

# Must be set before app.config is imported anywhere.
_fd, _db_path = tempfile.mkstemp(suffix=".sqlite3")
os.close(_fd)
os.environ["DATABASE_URL"] = f"sqlite+pysqlite:///{_db_path}"
os.environ["ENVIRONMENT"] = "test"

from app.database import Base, get_db  # noqa: E402
from app.main import app  # noqa: E402

test_engine = create_engine(
    f"sqlite+pysqlite:///{_db_path}", connect_args={"check_same_thread": False}
)


@event.listens_for(test_engine, "connect")
def _enforce_foreign_keys(dbapi_connection, _record):
    # SQLite ignores FOREIGN KEY constraints unless asked, which would let the
    # tests pass while Postgres rejected the same data. Turn them on so the two
    # engines disagree about as little as possible.
    cur = dbapi_connection.cursor()
    cur.execute("PRAGMA foreign_keys=ON")
    cur.close()


TestSession = sessionmaker(bind=test_engine, autoflush=False, autocommit=False)


@pytest.fixture(autouse=True)
def _fresh_schema() -> Generator[None, None, None]:
    Base.metadata.create_all(test_engine)
    yield
    Base.metadata.drop_all(test_engine)


@pytest.fixture
def client() -> Generator[TestClient, None, None]:
    def _override() -> Generator:
        db = TestSession()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = _override
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


@pytest.fixture
def seeded(client: TestClient) -> dict[str, int]:
    d = client.post(
        "/api/doctors", json={"name": "Dr Aparna Rao", "specialty": "Cardiology", "room": "C-12"}
    ).json()
    p = client.post(
        "/api/patients", json={"name": "Rahul Menon", "phone": "+91-9000000001"}
    ).json()
    return {"doctor_id": d["id"], "patient_id": p["id"]}
