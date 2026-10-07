"""Task API — the application at the centre of the final project.

Deliberately small, but with everything the pipeline needs to exercise:
health and readiness endpoints, Prometheus metrics, configuration from the
environment, and persistence to a mounted volume.
"""
import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

VERSION = os.getenv("APP_VERSION", "1.0.0")
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")
FEATURE_METRICS = os.getenv("FEATURE_METRICS", "true").lower() == "true"
DATA_DIR = os.getenv("DATA_DIR", "/data")

# Credentials come from a Secret, never from source.
DB_PASSWORD = os.getenv("DB_PASSWORD", "")
API_KEY = os.getenv("API_KEY", "")

_lock = threading.Lock()
_metrics = {"requests_total": 0, "errors_total": 0, "tasks_created": 0}
_started = time.time()


def _store():
    """Tasks persist to the mounted volume, so they survive a pod restart."""
    return os.path.join(DATA_DIR, "tasks.json")


def load_tasks():
    try:
        with open(_store()) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return []


def save_tasks(tasks):
    os.makedirs(DATA_DIR, exist_ok=True)
    tmp = _store() + ".tmp"
    with open(tmp, "w") as f:
        json.dump(tasks, f)
    os.replace(tmp, _store())   # atomic, so a crash mid-write cannot corrupt it


def add_task(title):
    if not title:
        raise ValueError("title is required")
    tasks = load_tasks()
    tasks.append({"id": len(tasks) + 1, "title": title})
    save_tasks(tasks)
    return tasks[-1]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, code, payload, ctype="application/json"):
        body = (payload if isinstance(payload, bytes) else json.dumps(payload).encode())
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        with _lock:
            _metrics["requests_total"] += 1

        if self.path == "/health":
            return self._send(200, {"status": "healthy"})

        if self.path == "/ready":
            # Readiness is stricter than liveness: it checks the dependency
            # (the data volume) is actually usable, not just that the process
            # is alive.
            try:
                os.makedirs(DATA_DIR, exist_ok=True)
                probe = os.path.join(DATA_DIR, ".ready")
                with open(probe, "w") as f:
                    f.write("ok")
                os.remove(probe)
                return self._send(200, {"status": "ready"})
            except OSError as exc:
                with _lock:
                    _metrics["errors_total"] += 1
                return self._send(503, {"status": "not ready", "reason": str(exc)})

        if self.path == "/metrics" and FEATURE_METRICS:
            return self._send(200, self._prometheus().encode(), "text/plain")

        if self.path == "/tasks":
            return self._send(200, {"tasks": load_tasks()})

        if self.path == "/":
            return self._send(200, {
                "app": "task-api",
                "version": VERSION,
                "environment": ENVIRONMENT,
                "hostname": os.uname().nodename,
                "tasks": len(load_tasks()),
                "secrets_loaded": bool(DB_PASSWORD) and bool(API_KEY),
            })

        with _lock:
            _metrics["errors_total"] += 1
        self._send(404, {"error": "not found"})

    def do_POST(self):
        with _lock:
            _metrics["requests_total"] += 1
        if self.path != "/tasks":
            return self._send(404, {"error": "not found"})
        length = int(self.headers.get("Content-Length", 0))
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
            task = add_task(payload.get("title", ""))
        except (ValueError, json.JSONDecodeError) as exc:
            with _lock:
                _metrics["errors_total"] += 1
            return self._send(400, {"error": str(exc)})
        with _lock:
            _metrics["tasks_created"] += 1
        self._send(201, task)

    def _prometheus(self):
        with _lock:
            m = dict(_metrics)
        return "\n".join([
            "# HELP taskapi_requests_total Total HTTP requests.",
            "# TYPE taskapi_requests_total counter",
            f"taskapi_requests_total {m['requests_total']}",
            "# HELP taskapi_errors_total Total error responses.",
            "# TYPE taskapi_errors_total counter",
            f"taskapi_errors_total {m['errors_total']}",
            "# HELP taskapi_tasks_created_total Tasks created.",
            "# TYPE taskapi_tasks_created_total counter",
            f"taskapi_tasks_created_total {m['tasks_created']}",
            "# HELP taskapi_uptime_seconds Seconds since start.",
            "# TYPE taskapi_uptime_seconds counter",
            f"taskapi_uptime_seconds {time.time() - _started:.1f}",
            "",
        ])


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8000"))
    HTTPServer(("0.0.0.0", port), Handler).serve_forever()  # nosec B104 - containers must bind all interfaces
