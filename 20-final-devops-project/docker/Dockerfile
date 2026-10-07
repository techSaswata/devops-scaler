# Multi-stage: the build stage carries pip and the toolchain, the runtime stage
# carries neither. Fewer packages in the final image means a smaller attack
# surface for the container scanner to find CVEs in.
FROM python:3.12-slim AS build
WORKDIR /build
COPY requirements.txt .
# mkdir first: this application has no third-party dependencies, so pip
# installs nothing and would never create /install - making the COPY in the
# next stage fail with "/install: not found". Creating it unconditionally keeps
# the multi-stage pattern working whether or not there are dependencies.
RUN mkdir -p /install \
 && pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000 \
    DATA_DIR=/data

# Patch the base image's OS packages — this is what the image scanner grades.
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*

COPY --from=build /install /usr/local
WORKDIR /app
COPY src/ ./src/

# Non-root, with a writable data dir. readOnlyRootFilesystem in the manifest
# means /data must come from a volume.
RUN useradd --create-home --uid 10001 appuser \
 && mkdir -p /data && chown -R appuser:appuser /app /data
USER 10001

EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health').status==200 else 1)"
CMD ["python", "-m", "src.app"]
