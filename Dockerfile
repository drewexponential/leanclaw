ARG OPENCLAW_VERSION=2026.4.2
FROM ghcr.io/openclaw/openclaw:${OPENCLAW_VERSION} AS base

ENV OPENCLAW_CONFIG_PATH=/data/state/openclaw.json \
    OPENCLAW_STATE_DIR=/data/state \
    OPENCLAW_NO_RESPAWN=1 \
    OPENCLAW_PREFER_PNPM=1

USER root

RUN apt-get update && apt-get install -y --no-install-recommends jq && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
COPY config/ /config/
COPY plugins/ /opt/plugins/
RUN chmod +x /entrypoint.sh

USER node
ENTRYPOINT ["/entrypoint.sh"]

# ---

FROM base AS tailscale

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg \
 && curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg \
      | tee /usr/share/keyrings/tailscale-archive-keyring.gpg > /dev/null \
 && curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list \
      | tee /etc/apt/sources.list.d/tailscale.list \
 && apt-get update && apt-get install -y --no-install-recommends tailscale \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /var/run/tailscale \
 && chown node:node /var/run/tailscale

USER node
