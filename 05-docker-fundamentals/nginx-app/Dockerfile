FROM nginx:alpine

LABEL maintainer="Saswata Das <24BCS10248>"
LABEL description="Hello World static page served by Nginx"

# Replace the stock nginx welcome page with our own
RUN rm -rf /usr/share/nginx/html/*
COPY index.html /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1/health || exit 1

# The base image's CMD already starts nginx in the foreground, but being explicit
# documents it. "daemon off;" is essential: a backgrounded nginx would let PID 1
# exit and the container would immediately stop.
CMD ["nginx", "-g", "daemon off;"]
