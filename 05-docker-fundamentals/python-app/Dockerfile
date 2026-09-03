# -slim is the sweet spot: full CPython, but without the build toolchain and docs
FROM python:3.12-slim

LABEL maintainer="Saswata Das <24BCS10248>"
LABEL description="Hello World web application in Python (Flask)"

# Don't write .pyc files; don't buffer stdout so logs appear immediately in `docker logs`
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=5000

WORKDIR /app

# Requirements first so the pip layer is cached independently of the source
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

RUN useradd --create-home --shell /bin/bash app && chown -R app:app /app
USER app

EXPOSE 5000

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:5000/health').status==200 else 1)"

CMD ["python", "app.py"]
