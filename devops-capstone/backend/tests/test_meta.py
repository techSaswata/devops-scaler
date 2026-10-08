"""Probe and metrics endpoints."""


def test_health_is_cheap_and_always_ok(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "healthy"


def test_ready_reports_the_database(client):
    r = client.get("/ready")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ready"
    assert body["database"] == "reachable"


def test_metrics_is_prometheus_format(client):
    client.get("/health")          # generate at least one observation
    r = client.get("/metrics")
    assert r.status_code == 200
    body = r.text
    # The exposition format, not merely "some text came back".
    assert "# HELP" in body and "# TYPE" in body
    assert "http_requests_total" in body


def test_root_reports_identity(client):
    r = client.get("/")
    assert r.status_code == 200
    assert r.json()["app"] == "ClinicFlow"
