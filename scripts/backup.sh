#!/bin/sh
# backup.sh — create a backup of the running leanclaw instance and download it
#
# Usage:
#   ./scripts/backup.sh [output-path]
#
# Default output: ./openclaw-backup.tar.gz

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
FLY_TOML="$ROOT_DIR/fly.toml"

die()  { echo "error: $1" >&2; exit 1; }
info() { echo "==> $1"; }

APP=$(grep "^app " "$FLY_TOML" | sed 's/.*= *"\(.*\)"/\1/')
[ -z "$APP" ] && die "could not read 'app' from fly.toml"

OUTPUT="${1:-$ROOT_DIR/openclaw-backup.tar.gz}"

info "Creating backup on $APP..."

# Remote script: run backup as node, echo the archive path on its own line
REMOTE_SCRIPT=$(mktemp)
cat > "$REMOTE_SCRIPT" << 'SCRIPT'
#!/bin/sh
set -e
su node -c "openclaw backup create --output /data --verify"
SCRIPT

flyctl sftp shell --app "$APP" << ENDSSH
put $REMOTE_SCRIPT /data/backup.sh
ENDSSH
rm -f "$REMOTE_SCRIPT"

REMOTE_PATH=$(flyctl ssh console --app "$APP" --command "sh /data/backup.sh" \
  | grep -oE '/data/[^[:space:]]+-openclaw-backup\.tar\.gz' | tail -1)

flyctl ssh console --app "$APP" --command "rm -f /data/backup.sh"

[ -z "$REMOTE_PATH" ] && die "could not determine backup path from command output"
info "Backup created at $REMOTE_PATH"

info "Downloading to $OUTPUT..."
flyctl sftp shell --app "$APP" << ENDSSH
get $REMOTE_PATH $OUTPUT
ENDSSH

flyctl ssh console --app "$APP" --command "rm -f $REMOTE_PATH"

echo ""
echo "Saved: $OUTPUT"
