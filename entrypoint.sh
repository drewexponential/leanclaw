#!/bin/sh
set -e

if [ ! -f /data/openclaw.json ]; then
  cat > /data/openclaw.json << 'EOF'
{
  "meta": {},
  "agents": {
    "defaults": {
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
    "controlUi": { "enabled": false }
  },
  "plugins": {
    "allow": ["telegram", "ollama"]
  }
}
EOF
fi

exec node dist/index.js gateway --allow-unconfigured --port 3000 --bind lan
