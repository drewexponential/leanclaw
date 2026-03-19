# leanclaw

A minimal Fly.io deployment wrapper for [openclaw](https://github.com/openclaw/openclaw).

## Prerequisites

- [flyctl](https://fly.io/docs/hands-on/install-flyctl/)
- A [Fly.io](https://fly.io) account
- An [Anthropic API key](https://console.anthropic.com/settings/keys)
- A Telegram bot token — create via [@BotFather](https://t.me/botfather) (`/newbot`, then `/setprivacy` → Disable)

## 1. Configure

Set your app name and nearest Fly.io region in `fly.toml`:

```toml
app            = "my-openclaw"
primary_region = "ord"
```

## 2. Deploy

```bash
flyctl auth login
./scripts/provision.sh up
```

Reads `app` and `primary_region` from `fly.toml`, prompts for secrets, then creates the app, volume, and deploys. The gateway starts and writes a default config to `/data/openclaw.json`.

## 3. Configure

SSH in to set your model and Telegram user ID, then restart:

```bash
flyctl ssh console
su node
openclaw config set agents.defaults.model.primary 'anthropic/claude-sonnet-4-6'
openclaw config set channels.telegram.allowFrom '[<your-telegram-id>]'
exit
exit
flyctl machine restart
```

Find your Telegram user ID via [@userinfobot](https://t.me/userinfobot). The `su node` is required — running `openclaw` as root creates state directories that the gateway cannot write to. Use `su node` without the dash: `su - node` starts a login shell that drops the container's environment variables.

Send your bot a DM to verify it responds.

## Backup

```bash
./scripts/backup.sh
```

Creates a backup on the running instance, downloads it to `./openclaw-backup.tar.gz`, and removes the remote copy. Pass an explicit path to save elsewhere.

## Restore from backup

If you have an existing openclaw backup, restore it before configuring manually:

```bash
./scripts/restore.sh openclaw-backup.tar.gz
```

Restores credentials, session history, cron jobs, identity, and workspace files (SOUL.md, AGENTS.md, etc.). Applies `channels.telegram.allowFrom` from the backup automatically. Never overwrites `openclaw.json` — leanclaw's defaults always stand.

Re-set secrets after a restore (not included in backups):

```bash
flyctl secrets set ANTHROPIC_API_KEY=<your-key>
flyctl secrets set TELEGRAM_BOT_TOKEN=<your-token>
```

## Teardown

```bash
./scripts/provision.sh down
```

Destroys the app and its volumes. Prompts for confirmation.

## Version management

`OPENCLAW_VERSION` in `fly.toml` is currently set to `latest`. ghcr.io image tags do not reliably match openclaw's reported version numbers — use `openclaw --version` via SSH to identify what's actually running.

```bash
flyctl ssh console --command "openclaw --version"
```

To pin a specific build once a known-good image tag is confirmed, update `OPENCLAW_VERSION` in `fly.toml` and commit.
