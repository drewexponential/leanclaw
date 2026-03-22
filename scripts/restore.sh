#!/bin/sh
# restore.sh — import an openclaw backup into a running leanclaw instance
#
# Usage:
#   ./scripts/restore.sh <backup.tar.gz>
#
# What gets restored:
#   - Everything under the state dir (credentials, sessions, workspace, cron, etc.)
#   - Separate workspace asset if present (old-style backups where stateDir was /data)
#
# What is never restored directly:
#   - openclaw.json — placed as openclaw.restore.json; entrypoint merges it on next start
#   - openclaw.json.bak* — skipped
#   - BOOTSTRAP.md — triggers openclaw's init ritual, must never be restored

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
FLY_TOML="$ROOT_DIR/fly.toml"

die()  { echo "error: $1" >&2; exit 1; }
info() { echo "==> $1"; }

BACKUP="${1:-}"
[ -z "$BACKUP" ] && { echo "Usage: $0 <backup.tar.gz>"; exit 1; }
[ -f "$BACKUP" ] || die "file not found: $BACKUP"

APP=$(grep "^app " "$FLY_TOML" | sed 's/.*= *"\(.*\)"/\1/')
[ -z "$APP" ] && die "could not read 'app' from fly.toml"

ARCHIVE_ROOT=$(tar -tzf "$BACKUP" 2>/dev/null | head -1 | cut -d/ -f1)
[ -z "$ARCHIVE_ROOT" ] && die "could not determine archive root from tarball"

# Read manifest
MANIFEST=$(tar -xzf "$BACKUP" --to-stdout "$ARCHIVE_ROOT/manifest.json" 2>/dev/null)
[ -z "$MANIFEST" ] && die "could not read manifest.json from backup"

# Derive state payload prefix from stateDir
SOURCE_STATE_DIR=$(echo "$MANIFEST" | grep '"stateDir"' | sed 's/.*"stateDir": *"\(.*\)".*/\1/')
[ -z "$SOURCE_STATE_DIR" ] && die "could not read stateDir from manifest"
STATE_SUFFIX=$(echo "$SOURCE_STATE_DIR" | sed 's|^/||')
STATE_PAYLOAD="$ARCHIVE_ROOT/payload/posix/$STATE_SUFFIX"

# Derive workspace payload if it exists as a separate asset (old-style backups)
WORKSPACE_PAYLOAD=$(echo "$MANIFEST" \
  | grep -A 2 '"kind": "workspace"' \
  | grep '"archivePath"' \
  | sed 's/.*"archivePath": *"\(.*\)".*/\1/')

info "App:             $APP"
info "Archive root:    $ARCHIVE_ROOT"
info "Source stateDir: $SOURCE_STATE_DIR"
echo ""

info "Uploading backup and restore script..."

REMOTE_SCRIPT=$(mktemp)
cat > "$REMOTE_SCRIPT" << SCRIPT
#!/bin/sh
set -e
ARCHIVE_ROOT="$ARCHIVE_ROOT"
STATE_PAYLOAD="$STATE_PAYLOAD"
WORKSPACE_PAYLOAD="$WORKSPACE_PAYLOAD"

# --- State: extract everything except openclaw.json and BOOTSTRAP.md ---
tar -xzf /data/restore.tar.gz -C /tmp "\$STATE_PAYLOAD"
PSRC="/tmp/\$STATE_PAYLOAD"
mkdir -p /data/state

for item in "\$PSRC"/*; do
  name=\$(basename "\$item")
  case "\$name" in
    openclaw.json)
      cp "\$item" /data/state/openclaw.restore.json
      echo "Staged \$name as openclaw.restore.json (entrypoint will merge on next start)"
      ;;
    openclaw.json.bak*) echo "Skipping \$name" ;;
    *) cp -r "\$item" /data/state/ ;;
  esac
done

rm -f /data/state/workspace/BOOTSTRAP.md
chown -R node:node /data/state
echo "State restored."

# --- Workspace: separate asset (old-style backups only) ---
if [ -n "\$WORKSPACE_PAYLOAD" ]; then
  tar -xzf /data/restore.tar.gz -C /tmp \
    --exclude='*/workspace/.git' \
    --exclude='*/workspace/.git/*' \
    "\$WORKSPACE_PAYLOAD"
  mkdir -p /data/state/workspace
  cp -r "/tmp/\$WORKSPACE_PAYLOAD/." /data/state/workspace/
  rm -f /data/state/workspace/BOOTSTRAP.md
  chown -R node:node /data/state/workspace
  echo "Workspace (separate asset) restored."
fi

rm -rf /data/restore.tar.gz /data/restore.sh /tmp/"\$ARCHIVE_ROOT"
echo "Restore complete."
SCRIPT

flyctl sftp shell --app "$APP" << ENDSSH
put $BACKUP /data/restore.tar.gz
put $REMOTE_SCRIPT /data/restore.sh
ENDSSH

rm -f "$REMOTE_SCRIPT"

info "Restoring state and workspace..."
flyctl ssh console --app "$APP" --command "sh /data/restore.sh"

info "Restarting machine..."
flyctl machine restart --app "$APP"

echo ""
echo "Done. Waiting for openclaw to spin back up."
echo "Check logs with: flyctl logs --app $APP"
echo "Once the gateway is running, send your bot a Telegram DM to verify the restore."
