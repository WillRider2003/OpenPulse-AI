FROM ubuntu:24.04
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y asterisk \
 && rm -rf /var/lib/apt/lists/*
EXPOSE 5060/udp 10000-10100/udp
CMD ["asterisk", "-f", "-vvv"]
