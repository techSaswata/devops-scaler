"""Configuration, read from the environment and nowhere else.

The same image runs in compose, in kind and on EKS; only the environment
differs. Nothing here has a production default that would let a misconfigured
deployment start up and silently talk to the wrong database.
"""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # postgresql+psycopg://user:password@host:5432/dbname
    database_url: str = "postgresql+psycopg://clinic:clinic@localhost:5432/clinicflow"

    app_name: str = "ClinicFlow"
    app_version: str = "1.0.0"
    environment: str = "development"
    log_level: str = "INFO"

    # Seconds a slot occupies by default when none is given.
    default_slot_minutes: int = 30


settings = Settings()
