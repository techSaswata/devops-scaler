# Alpine keeps the image tiny (~135MB vs ~1.1GB for the full node image)
FROM node:20-alpine

# Metadata
LABEL maintainer="Saswata Das <24BCS10248>"
LABEL description="Hello World web application in Node.js"

WORKDIR /app

# Copy the manifest FIRST and install deps separately, so Docker can cache the
# dependency layer and skip re-installing when only the source changes.
COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force

COPY server.js ./

# Don't run as root: create an unprivileged user and drop to it.
RUN addgroup -S app && adduser -S app -G app && chown -R app:app /app
USER app

ENV PORT=3000
EXPOSE 3000

HEALTHCHECK --interval=10s --timeout=3s --start-period=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/health || exit 1

CMD ["node", "server.js"]
