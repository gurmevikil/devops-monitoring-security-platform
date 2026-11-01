# Pin the Python patch release and Debian release for repeatable base-image selection.
FROM python:3.11.17-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=5000

WORKDIR /app

# Run the service without root privileges inside the container.
RUN groupadd --system app && useradd --system --gid app --create-home app

# Copy dependencies first so Docker can reuse this layer when application code changes.
COPY app/requirements.txt ./requirements.txt
RUN python -m pip install --no-cache-dir --no-warn-script-location -r requirements.txt

COPY app/app.py ./app.py

USER app
EXPOSE 5000

# Docker reports the container unhealthy if this local endpoint stops responding.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/health', timeout=2)" || exit 1

# One worker keeps the in-memory Prometheus counters consistent for this learning demo.
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "1", "--access-logfile", "-", "--error-logfile", "-", "app:app"]
