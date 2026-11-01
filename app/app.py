"""Small Flask service with Prometheus instrumentation for the monitoring demo."""

import os
import time

from flask import Flask, Response, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest


APP_NAME = "devops-monitoring-demo"
APP_VERSION = os.getenv("APP_VERSION", "1.0.0")

app = Flask(__name__)

HTTP_REQUESTS = Counter(
    "http_requests_total",
    "Total HTTP requests handled by the application.",
    ("method", "endpoint", "status"),
)
HTTP_REQUEST_DURATION = Histogram(
    "http_request_duration_seconds",
    "Time spent handling HTTP requests, in seconds.",
    ("method", "endpoint"),
)
HTTP_ERRORS = Counter(
    "http_errors_total",
    "HTTP responses with a server error status (5xx).",
    ("method", "endpoint", "status"),
)
APP_AVAILABLE = Gauge(
    "app_available",
    "Whether this process has initialized and is serving requests (1=yes).",
)
APP_AVAILABLE.set(1)


@app.before_request
def start_request_timer():
    # Keep a monotonic start time per request. /metrics itself is excluded below
    # to avoid the scrape changing the application request counters.
    request._metrics_started_at = time.perf_counter()


@app.after_request
def record_request(response):
    if request.path != "/metrics":
        endpoint = request.endpoint or "unmatched"
        method = request.method
        status = str(response.status_code)
        HTTP_REQUESTS.labels(method=method, endpoint=endpoint, status=status).inc()
        if response.status_code >= 500:
            HTTP_ERRORS.labels(method=method, endpoint=endpoint, status=status).inc()
        started_at = getattr(request, "_metrics_started_at", None)
        if started_at is not None:
            HTTP_REQUEST_DURATION.labels(method=method, endpoint=endpoint).observe(
                time.perf_counter() - started_at
            )
    return response


@app.get("/")
def home():
    return (
        "<!doctype html><title>DevOps Monitoring Demo</title>"
        "<h1>DevOps Monitoring and Security Automation Platform</h1>"
        "<p>Try <a href='/health'>/health</a>, <a href='/info'>/info</a>, "
        "<a href='/api/hello'>/api/hello</a>, and <a href='/metrics'>/metrics</a>.</p>"
    )


@app.get("/health")
def health():
    return jsonify(status="healthy", application=APP_NAME), 200


@app.get("/info")
def info():
    return jsonify(name=APP_NAME, version=APP_VERSION, environment=os.getenv("APP_ENV", "local"))


@app.get("/api/hello")
def hello():
    return jsonify(message="Hello from the DevOps monitoring demo!"), 200


@app.get("/api/items")
def items():
    return jsonify(items=[{"id": 1, "name": "metrics"}, {"id": 2, "name": "monitoring"}])


@app.get("/api/error")
def intentional_error():
    """Generate a controlled 500 response to demonstrate error metrics/alerts."""
    app.logger.error("Intentional demo error requested")
    return jsonify(error="intentional demo error"), 500


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    # Flask's built-in server is for local learning only. A later Docker phase
    # will use a production WSGI server for the container.
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "5000")), debug=False)
