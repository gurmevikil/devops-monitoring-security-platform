# Pin a supported Python patch release and Debian release. Refresh installed
# Debian packages at build time so the image includes available security fixes.
FROM python:3.12.16-slim-trixie

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=5000

WORKDIR /app

RUN apt-get update \
    && apt-get upgrade --yes --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

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
    CMD python -c "import urllib.request; urllib.request.urlopen('http://[::1]:5000/health', timeout=2)" || exit 1

# One worker keeps the in-memory Prometheus counters consistent for this learning demo.
CMD ["gunicorn", "--bind", "[::]:5000", "--workers", "1", "--access-logfile", "-", "--error-logfile", "-", "app:app"]
