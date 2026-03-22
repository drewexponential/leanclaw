#!/bin/sh
set -e

mkdir -p /data/state /data/state/workspace /data/tailscale

# Merge config layers: base → overrides
jq -s '.[0] * .[1]' /config/leanclaw-base.json /config/leanclaw-overrides.json > /tmp/merged.json

# Inject TELEGRAM_ALLOW_FROM if set
if [ -n "${TELEGRAM_ALLOW_FROM}" ]; then
  jq --argjson allow "${TELEGRAM_ALLOW_FROM}" \
    '.channels.telegram.allowFrom = $allow' \
    /tmp/merged.json > /tmp/merged2.json && mv /tmp/merged2.json /tmp/merged.json
fi

# Inject BRAVE_API_KEY if set
if [ -n "${BRAVE_API_KEY}" ]; then
  jq --arg key "${BRAVE_API_KEY}" \
    '.tools.web.search = {"enabled": true, "provider": "brave", "apiKey": $key}' \
    /tmp/merged.json > /tmp/merged2.json && mv /tmp/merged2.json /tmp/merged.json
fi

# If a restore config exists, merge it on top (backup wins on conflicts), then delete it
if [ -f /data/state/openclaw.restore.json ]; then
  jq -s '.[0] * .[1]' /tmp/merged.json /data/state/openclaw.restore.json > /tmp/merged2.json \
    && mv /tmp/merged2.json /tmp/merged.json
  rm -f /data/state/openclaw.restore.json
fi

cp /tmp/merged.json /data/state/openclaw.json

if [ -n "${TAILSCALE_AUTHKEY}" ]; then
  tailscaled \
    --tun=userspace-networking \
    --state=/data/tailscale/state \
    &

  until tailscale status > /dev/null 2>&1; do
    sleep 1
  done

  tailscale up \
    --authkey="${TAILSCALE_AUTHKEY}" \
    --hostname="${FLY_APP_NAME:-openclaw}" \
    --accept-routes=false \
    --ssh=false

  exec node dist/index.js gateway --allow-unconfigured --port 3000 --bind lan --tailscale serve --tailscale-reset-on-exit
else
  exec node dist/index.js gateway --allow-unconfigured --port 3000 --bind lan
fi
