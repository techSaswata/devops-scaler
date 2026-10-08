"""ClinicFlow API.

Three probe endpoints, and the difference between them is the whole point:

  /health  liveness  -- is this process answering at all? Cheap, no I/O. Its
                        remedy is a kill, so it must not fail for reasons a
                        restart cannot fix. If it touched the database, a brief
                        database outage would make Kubernetes restart every
                        healthy pod in the deployment, turning a recoverable
                        blip into an outage.
  /ready   readiness -- can this process serve traffic right now? It DOES touch
                        the database, because an API that cannot reach Postgres
                        cannot answer, and the correct response is to leave the
                        Service endpoints until it can.
  /metrics           -- Prometheus exposition, added by the instrumentator.
"""
import logging

from fastapi import FastAPI, Response, status
from fastapi.middleware.cors import CORSMiddleware
from prometheus_fastapi_instrumentator import Instrumentator
from sqlalchemy import text

from app.config import settings
from app.database import engine
from app.routers import appointments, doctors, patients

logging.basicConfig(level=settings.log_level)
log = logging.getLogger("clinicflow")

app = FastAPI(
    title=f"{settings.app_name} API",
    version=settings.app_version,
    description="Appointment management for a small clinic.",
)

# The browser never calls the backend cross-origin in production -- nginx and
# the Ingress put both behind one origin. This is for `vite dev` on :5173.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://localhost:3000"],
    allow_methods=["*"],
    allow_headers=["*"],
)

Instrumentator().instrument(app).expose(app, endpoint="/metrics", include_in_schema=True)

app.include_router(doctors.router)
app.include_router(patients.router)
app.include_router(appointments.router)


@app.get("/", tags=["meta"])
def root() -> dict[str, str]:
    return {
        "app": settings.app_name,
        "version": settings.app_version,
        "environment": settings.environment,
        "docs": "/docs",
    }


@app.get("/health", tags=["meta"])
def health() -> dict[str, str]:
    return {"status": "healthy"}


@app.get("/ready", tags=["meta"])
def ready(response: Response) -> dict[str, str]:
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return {"status": "ready", "database": "reachable"}
    except Exception as exc:                      # noqa: BLE001 - report, never crash
        # A readiness probe must answer. Letting this raise would return 500,
        # which Kubernetes also treats as not-ready, but the log line below is
        # what makes the cause findable.
        log.warning("readiness check failed: %s", exc)
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {"status": "not ready", "database": "unreachable"}
