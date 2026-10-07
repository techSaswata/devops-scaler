"""A small Flask API used as the subject of the CI/CD pipeline."""
import os
from flask import Flask, jsonify

app = Flask(__name__)
VERSION = os.getenv("APP_VERSION", "1.0.0")


def add(a: int, b: int) -> int:
    """Add two numbers."""
    return a + b


def divide(a: float, b: float) -> float:
    """Divide a by b. Raises on division by zero."""
    if b == 0:
        raise ValueError("division by zero")
    return a / b


@app.route("/")
def index():
    return jsonify(app="cicd-demo", version=VERSION, status="ok")


@app.route("/health")
def health():
    return jsonify(status="healthy"), 200


@app.route("/add/<int:a>/<int:b>")
def add_route(a, b):
    return jsonify(result=add(a, b))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "5000")))
