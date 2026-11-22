FROM ubuntu:24.04

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    asterisk \
    iproute2 \
    nftables \
    fail2ban \
    tcpdump \
    openssl \
    python3 \
    ca-certificates \
    procps \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 5060/udp 5061/tcp 8088/tcp 8089/tcp 10000-10100/udp
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
