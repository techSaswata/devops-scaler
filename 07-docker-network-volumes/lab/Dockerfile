# A small toolbox image so the frontend/backend containers can actually TEST
# connectivity (ping, dig, curl, mysql client) instead of just existing.
FROM alpine:latest
RUN apk add --no-cache \
      curl bind-tools iputils busybox-extras \
      mysql-client netcat-openbsd iproute2
CMD ["sleep", "infinity"]
