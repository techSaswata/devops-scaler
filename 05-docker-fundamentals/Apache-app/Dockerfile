FROM httpd:2.4

LABEL maintainer="Saswata Das <24BCS10248>"
LABEL description="Hello World static page served by the Apache HTTP Server"

# Apache's DocumentRoot in this image is /usr/local/apache2/htdocs
# (note: NOT /var/www/html — that's the Debian package layout, a common mix-up)
RUN rm -f /usr/local/apache2/htdocs/index.html
COPY index.html /usr/local/apache2/htdocs/

EXPOSE 80

# NOTE: the httpd:2.4 image ships neither curl nor wget, so a `CMD curl ...`
# healthcheck fails with "curl: not found" and marks the container UNHEALTHY even
# though Apache is serving fine. bash's /dev/tcp built-in needs no extra packages
# and keeps the image lean.
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD bash -c 'exec 3<>/dev/tcp/127.0.0.1/80 && printf "GET / HTTP/1.0\r\n\r\n" >&3 && head -1 <&3 | grep -q 200' || exit 1

# httpd-foreground is the image's own entrypoint script; it runs Apache in the
# foreground so PID 1 stays alive.
CMD ["httpd-foreground"]
