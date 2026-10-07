# Multi-stage: the build stage has pip and a compiler; the runtime stage has
# neither, which removes a large slice of the image's attack surface.
FROM python:3.12-slim AS build
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PORT=5000

# Patch the base image's OS packages - this is what an image scanner grades.
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*

COPY --from=build /install /usr/local
WORKDIR /app
COPY src/ ./src/

# Run as a non-root user. Scanners and admission controllers both check this.
RUN useradd --create-home --uid 10001 appuser && chown -R appuser:appuser /app
USER 10001

EXPOSE 5000
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:5000/health').status==200 else 1)"
CMD ["python", "-m", "src.app"]
