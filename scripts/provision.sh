#!/bin/sh
# provision.sh — create or destroy a leanclaw Fly.io deployment
#
# Usage:
#   ./scripts/provision.sh up      — create app, volume, set secrets, deploy
#   ./scripts/provision.sh down    — destroy app and its volumes

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
FLY_TOML="$ROOT_DIR/fly.toml"

die() { echo "error: $1" >&2; exit 1; }

get_toml_value() {
  grep "^$1 " "$FLY_TOML" | sed 's/.*= *"\(.*\)"/\1/'
}

cmd_up() {
  APP=$(get_toml_value app)
  REGION=$(get_toml_value primary_region)

  [ -z "$APP" ]    && die "could not read 'app' from fly.toml"
  [ -z "$REGION" ] && die "could not read 'primary_region' from fly.toml"

  echo "App:    $APP"
  echo "Region: $REGION"
  echo ""

  printf "ANTHROPIC_API_KEY: "
  read -rs ANTHROPIC_KEY
  echo ""
  [ -z "$ANTHROPIC_KEY" ] && die "ANTHROPIC_API_KEY is required"

  printf "TELEGRAM_BOT_TOKEN: "
  read -rs TELEGRAM_TOKEN
  echo ""
  [ -z "$TELEGRAM_TOKEN" ] && die "TELEGRAM_BOT_TOKEN is required"

  echo ""
  echo "Tailscale (optional)"
  echo "  Enables remote openclaw clients — such as agents running on other machines —"
  echo "  to connect to this gateway over a private Tailscale network. Without it,"
  echo "  the gateway is only reachable within Fly.io's private network (Telegram"
  echo "  and other outbound channels work fine either way)."
  printf "Enable Tailscale? [y/N]: "
  read -r TAILSCALE_CHOICE
  echo ""

  TAILSCALE_KEY=""
  if [ "$TAILSCALE_CHOICE" = "y" ] || [ "$TAILSCALE_CHOICE" = "Y" ]; then
    echo "  Generate a reusable, pre-authorized auth key in the Tailscale admin"
    echo "  console (Settings → Keys). Ephemeral keys will not survive restarts."
    echo ""
    printf "TAILSCALE_AUTHKEY: "
    read -rs TAILSCALE_KEY
    echo ""
    [ -z "$TAILSCALE_KEY" ] && die "TAILSCALE_AUTHKEY is required when Tailscale is enabled"
  fi

  echo ""
  echo "==> Creating app..."
  flyctl apps create "$APP"

  echo "==> Creating volume..."
  flyctl volumes create openclaw_data \
    --app "$APP" \
    --region "$REGION" \
    --size 1 \
    --yes

  echo "==> Setting secrets..."
  if [ -n "$TAILSCALE_KEY" ]; then
    flyctl secrets set --app "$APP" \
      "ANTHROPIC_API_KEY=$ANTHROPIC_KEY" \
      "TELEGRAM_BOT_TOKEN=$TELEGRAM_TOKEN" \
      "TAILSCALE_AUTHKEY=$TAILSCALE_KEY"
  else
    flyctl secrets set --app "$APP" \
      "ANTHROPIC_API_KEY=$ANTHROPIC_KEY" \
      "TELEGRAM_BOT_TOKEN=$TELEGRAM_TOKEN"
  fi

  if [ -n "$TAILSCALE_KEY" ]; then
    echo "==> Enabling Tailscale build target..."
    sed -i '' 's/target     = "base"/target     = "tailscale"/' "$FLY_TOML"
  fi

  echo "==> Deploying..."
  flyctl deploy --app "$APP"

  echo ""
  echo "Done. Next steps:"
  echo "  - Configure: flyctl ssh console → su node → openclaw config set ..."
  echo "  - Restore:   ./scripts/restore.sh <backup.tar.gz>"
}

cmd_down() {
  APP=$(get_toml_value app)
  [ -z "$APP" ] && die "could not read 'app' from fly.toml"

  echo "This will permanently destroy app '$APP' and all its volumes."
  printf "Type the app name to confirm: "
  read -r CONFIRM

  [ "$CONFIRM" != "$APP" ] && { echo "Aborted."; exit 1; }

  echo "==> Collecting volume IDs..."
  VOLUME_IDS=$(flyctl volumes list --app "$APP" --json 2>/dev/null \
    | grep '"id"' | sed 's/.*"id": *"\([^"]*\)".*/\1/')

  echo "==> Destroying app..."
  flyctl apps destroy "$APP" --yes

  if [ -n "$VOLUME_IDS" ]; then
    echo "==> Destroying volumes..."
    for VOL_ID in $VOLUME_IDS; do
      flyctl volumes destroy "$VOL_ID" --yes 2>/dev/null || true
    done
  fi

  echo "Done."
}

case "${1:-}" in
  up)   cmd_up ;;
  down) cmd_down ;;
  *)
    echo "Usage: $0 <up|down>"
    exit 1
    ;;
esac
