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

  printf "TELEGRAM_ALLOW_FROM (comma-separated Telegram user IDs): "
  read -r TELEGRAM_ALLOW_FROM
  echo ""
  [ -z "$TELEGRAM_ALLOW_FROM" ] && die "TELEGRAM_ALLOW_FROM is required"

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
  echo "Web search (optional)"
  echo "  Enables the agent to search the web via Brave Search. Requires a"
  echo "  Brave Search API key (https://brave.com/search/api/)."
  printf "Enable web search? [y/N]: "
  read -r BRAVE_CHOICE
  echo ""

  BRAVE_KEY=""
  if [ "$BRAVE_CHOICE" = "y" ] || [ "$BRAVE_CHOICE" = "Y" ]; then
    printf "BRAVE_API_KEY: "
    read -rs BRAVE_KEY
    echo ""
    [ -z "$BRAVE_KEY" ] && die "BRAVE_API_KEY is required when web search is enabled"
  fi

  echo ""
  echo "GitHub (optional)"
  echo "  Enables the agent to push config changes and open PRs against this repo."
  echo "  Requires a fine-grained PAT with contents:write and pull_requests:write."
  printf "Enable GitHub integration? [y/N]: "
  read -r GITHUB_CHOICE
  echo ""

  GITHUB_TOKEN=""
  GITHUB_REPO=""
  if [ "$GITHUB_CHOICE" = "y" ] || [ "$GITHUB_CHOICE" = "Y" ]; then
    printf "GITHUB_TOKEN (fine-grained PAT): "
    read -rs GITHUB_TOKEN
    echo ""
    [ -z "$GITHUB_TOKEN" ] && die "GITHUB_TOKEN is required when GitHub integration is enabled"
    printf "GitHub repo (owner/repo, e.g. myorg/leanclaw): "
    read -r GITHUB_REPO
    echo ""
    [ -z "$GITHUB_REPO" ] && die "GitHub repo is required when GitHub integration is enabled"
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
  SECRETS="ANTHROPIC_API_KEY=$ANTHROPIC_KEY TELEGRAM_BOT_TOKEN=$TELEGRAM_TOKEN TELEGRAM_ALLOW_FROM=$TELEGRAM_ALLOW_FROM"
  [ -n "$TAILSCALE_KEY" ]  && SECRETS="$SECRETS TAILSCALE_AUTHKEY=$TAILSCALE_KEY"
  [ -n "$BRAVE_KEY" ]      && SECRETS="$SECRETS BRAVE_API_KEY=$BRAVE_KEY"
  [ -n "$GITHUB_TOKEN" ]   && SECRETS="$SECRETS GITHUB_TOKEN=$GITHUB_TOKEN"
  # shellcheck disable=SC2086
  flyctl secrets set --app "$APP" $SECRETS

  if [ -n "$TAILSCALE_KEY" ]; then
    echo "==> Enabling Tailscale build target..."
    sed -i '' 's/target     = "base"/target     = "tailscale"/' "$FLY_TOML"
  fi

  echo "==> Deploying..."
  flyctl deploy --app "$APP"

  if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
    echo "==> Cloning repo onto volume..."
    flyctl ssh console --app "$APP" --command \
      "git clone https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git /data/state/workspace/leanclaw 2>/dev/null || echo 'Repo already cloned or clone failed — skipping.'"
  fi

  echo ""
  echo "Done. Next steps:"
  echo "  - Restore:   ./scripts/restore.sh <backup.tar.gz>"
  [ -n "$GITHUB_TOKEN" ] && echo "  - Set FLY_API_TOKEN in GitHub repo secrets to enable auto-deploy on push"
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
