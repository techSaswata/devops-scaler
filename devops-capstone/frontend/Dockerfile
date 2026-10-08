# ---- build stage: Node toolchain, which must not survive into the runtime ----
FROM node:22-alpine AS build
WORKDIR /app

# package.json + lockfile first: this layer is cached unless the dependencies
# actually change, so a source-only edit skips the whole install.
COPY package.json package-lock.json* ./
RUN npm ci --no-audit --no-fund

COPY . .
RUN npm run build

# ---- runtime stage: static files and nginx, no Node at all ----
# nginx-unprivileged, not plain nginx. The stock image starts its master process
# as root and only drops privileges for workers; this one runs entirely as uid
# 101 and listens on 8080, so it also satisfies a readOnlyRootFilesystem-style
# securityContext without extra patching.
FROM nginxinc/nginx-unprivileged:1.27-alpine

# A template, not a finished config: the official entrypoint runs envsubst over
# /etc/nginx/templates, which is how BACKEND_HOST differs between compose
# (service name "backend") and Kubernetes (the Service DNS name) without
# rebuilding the image.
COPY --chown=101:101 default.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build --chown=101:101 /app/dist /usr/share/nginx/html

ENV BACKEND_HOST=backend \
    BACKEND_PORT=8000 \
    NGINX_ENVSUBST_OUTPUT_DIR=/etc/nginx/conf.d

USER 101
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz >/dev/null || exit 1
