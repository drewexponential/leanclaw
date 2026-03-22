#!/bin/sh
# secrets-push.sh — push one or more secrets to a running instance without teardown
#
# Usage:
#   ./scripts/secrets-push.sh KEY=value [KEY2=value2 ...]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
FLY_TOML="$ROOT_DIR/fly.toml"

die() { echo "error: $1" >&2; exit 1; }

[ $# -eq 0 ] && { echo "Usage: $0 KEY=value [KEY2=value2 ...]"; exit 1; }

APP=$(grep "^app " "$FLY_TOML" | sed 's/.*= *"\(.*\)"/\1/')
[ -z "$APP" ] && die "could not read 'app' from fly.toml"

echo "==> Setting secrets on $APP..."
# shellcheck disable=SC2068
flyctl secrets set --app "$APP" $@
echo "Done."
