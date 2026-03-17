ARG OPENCLAW_VERSION=2026.3.12
FROM ghcr.io/openclaw/openclaw:${OPENCLAW_VERSION}

USER root

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER node
ENTRYPOINT ["/entrypoint.sh"]
