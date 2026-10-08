# ---- build stage: wheels only, so the toolchain never reaches the runtime ----
FROM python:3.12-slim AS build
WORKDIR /build
RUN apt-get update && apt-get install -y --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt

# ---- runtime stage ----
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000

# Patch the base image's OS packages. This is the layer the image scanner
# grades, and the base is rebuilt on a schedule, so there are usually fixes
# waiting by the time it is pulled.
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*

COPY --from=build /wheels /wheels
COPY requirements.txt .
RUN pip install --no-cache-dir --no-index --find-links=/wheels -r requirements.txt \
 && rm -rf /wheels

WORKDIR /app
COPY alembic.ini ./
COPY alembic/ ./alembic/
COPY app/ ./app/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Non-root. The uid is explicit so the Kubernetes securityContext can assert the
# same number with runAsUser, rather than trusting whatever the image happens
# to have.
RUN useradd --create-home --uid 10001 appuser && chown -R appuser:appuser /app
USER 10001

EXPOSE 8000
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health').status==200 else 1)"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
