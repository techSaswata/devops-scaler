# ---------- Stage 1: BUILD the React bundle ----------
FROM node:20-alpine AS build

WORKDIR /app

# Install dependencies first so this layer caches independently of the source
COPY package.json ./
RUN npm install

# Now the source, then produce the optimised static bundle in /app/dist
COPY vite.config.js index.html ./
COPY src ./src
RUN npm run build

# ---------- Stage 2: SERVE the static files ----------
# Node is not needed at runtime — a React SPA compiles down to plain HTML/CSS/JS.
# Shipping nginx:alpine instead of node:20-alpine drops the image from ~400MB to ~50MB.
FROM nginx:alpine

LABEL maintainer="Saswata Das <24BCS10248>"
LABEL description="Hello World React SPA, built with Vite and served by Nginx"

RUN rm -rf /usr/share/nginx/html/*
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
