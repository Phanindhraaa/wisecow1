# Stage 1: Build / dependency installation
FROM ubuntu:22.04

LABEL maintainer="devops@example.com"
LABEL description="Wisecow – cow wisdom web server"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        fortune-mod \
        fortunes \
        fortunes-min \
        cowsay \
        netcat-openbsd \
        bash \
        openssl \
    && rm -rf /var/lib/apt/lists/*

# fortune binary lives in /usr/games, cowsay also in /usr/games
ENV PATH="/usr/games:/usr/local/games:${PATH}"

# Verify fortune works at build time – catches missing .dat files immediately
RUN fortune > /dev/null

WORKDIR /app

# Copy application script
COPY wisecow.sh /app/wisecow.sh
RUN chmod +x /app/wisecow.sh

# TLS certificates will be mounted at runtime via k8s Secret.
RUN mkdir -p /app/tls

# Expose the default Wisecow port
EXPOSE 4499

# Health-check so Kubernetes liveness probes have a fallback
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD nc -z localhost 4499 || exit 1

ENTRYPOINT ["/app/wisecow.sh"]
