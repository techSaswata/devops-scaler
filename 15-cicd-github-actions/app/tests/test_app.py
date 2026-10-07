"""Unit tests. The CI pipeline fails if any of these fail."""
import pytest

from src.app import add, divide, app


def test_add():
    assert add(2, 3) == 5
    assert add(-1, 1) == 0


def test_divide():
    assert divide(10, 2) == 5


def test_divide_by_zero_raises():
    with pytest.raises(ValueError):
        divide(1, 0)


def test_index_route():
    client = app.test_client()
    r = client.get("/")
    assert r.status_code == 200
    assert r.get_json()["app"] == "cicd-demo"


def test_health_route():
    client = app.test_client()
    assert client.get("/health").status_code == 200


def test_add_route():
    client = app.test_client()
    assert client.get("/add/2/3").get_json()["result"] == 5
