# Networking practice box: every tool the exercises need, baked in.
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN for i in 1 2 3; do \
      apt-get update -qq && \
      apt-get install -y --no-install-recommends \
        iproute2 net-tools dnsutils iputils-ping traceroute mtr-tiny \
        curl wget netcat-openbsd telnet tcpdump nmap whois procps \
        ca-certificates && break || sleep 5; \
    done && rm -rf /var/lib/apt/lists/*
CMD ["/bin/bash"]
