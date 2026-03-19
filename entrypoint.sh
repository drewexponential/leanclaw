#!/bin/sh
set -e

mkdir -p /data/state /data/state/workspace /data/tailscale

if [ ! -f /data/state/openclaw.json ]; then
  cat > /data/state/openclaw.json << 'EOF'
{
  "meta": {},
  "agents": {
    "defaults": {
      "workspace": "/data/state/workspace",
      "contextPruning": {
        "mode": "cache-ttl",
        "ttl": "1h"
      },
      "compaction": {
        "mode": "safeguard"
      },
      "heartbeat": {
        "every": "30m"
      },
      "maxConcurrent": 4,
      "subagents": {
        "maxConcurrent": 8
      }
    }
  },
  "messages": {
    "ackReactionScope": "group-mentions"
  },
  "commands": {
    "native": "auto",
    "nativeSkills": "auto",
    "restart": true,
    "ownerDisplay": "raw"
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "pairing",
      "groupPolicy": "allowlist",
      "streaming": "partial"
    }
  },
  "gateway": {
    "mode": "local",
    "controlUi": { "enabled": false }
  },
  "plugins": {
    "deny": ["googlechat", "matrix", "nostr", "tlon", "twitch", "zalouser"]
  }
}
EOF
fi

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
