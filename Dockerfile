FROM ubuntu:latest

# Install dependencies
RUN apt-get update && apt-get install -y \
    bash \
    openvpn \
    iptables \
    iproute2 \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# Copy scripts
COPY run.sh /
COPY up.sh /
COPY healthcheck.sh /
RUN sed -i 's/\r$//' /run.sh /up.sh /healthcheck.sh && chmod +x /run.sh /up.sh /healthcheck.sh

# Healthcheck for VPN and NAT
HEALTHCHECK --interval=15s --timeout=5s --retries=3 \
            CMD /healthcheck.sh

ENTRYPOINT ["/run.sh"]