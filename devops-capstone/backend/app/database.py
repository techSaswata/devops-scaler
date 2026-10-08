"""Engine, session factory and the FastAPI dependency.

pool_pre_ping matters in Kubernetes: a pod can outlive a database restart or a
NAT idle-timeout, and a pooled connection that died quietly would otherwise
surface as a 500 on a random request. pre_ping pays one cheap round-trip to
avoid that.
"""
from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import settings

engine = create_engine(
    settings.database_url,
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=10,
)

SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
