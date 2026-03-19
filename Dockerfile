ARG OPENCLAW_VERSION=2026.3.12
FROM ghcr.io/openclaw/openclaw:${OPENCLAW_VERSION}

ENV OPENCLAW_CONFIG_PATH=/data/state/openclaw.json \
    OPENCLAW_STATE_DIR=/data/state \
    OPENCLAW_NO_RESPAWN=1 \
    OPENCLAW_PREFER_PNPM=1

USER root

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER node
ENTRYPOINT ["/entrypoint.sh"]
