import json
import os
import tempfile

import pytest

import src.app as app_module
from src.app import add_task, load_tasks, save_tasks


@pytest.fixture(autouse=True)
def tmp_data(monkeypatch):
    """Point the app at a throwaway data dir for every test."""
    with tempfile.TemporaryDirectory() as d:
        monkeypatch.setattr(app_module, "DATA_DIR", d)
        yield d


def test_tasks_start_empty():
    assert load_tasks() == []


def test_add_task():
    t = add_task("write the README")
    assert t["id"] == 1 and t["title"] == "write the README"


def test_add_task_persists():
    add_task("one")
    add_task("two")
    assert [t["title"] for t in load_tasks()] == ["one", "two"]


def test_add_task_rejects_empty_title():
    with pytest.raises(ValueError):
        add_task("")


def test_save_is_atomic(tmp_data):
    save_tasks([{"id": 1, "title": "x"}])
    # The temp file must not be left behind - a crash mid-write would
    # otherwise leave a partial file that looks like real data.
    assert not os.path.exists(os.path.join(tmp_data, "tasks.json.tmp"))
    assert json.load(open(os.path.join(tmp_data, "tasks.json")))[0]["title"] == "x"


def test_metrics_format():
    h = app_module.Handler.__new__(app_module.Handler)
    body = h._prometheus()
    assert "# TYPE taskapi_requests_total counter" in body
    assert "taskapi_uptime_seconds" in body
