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
flyctl apps create <your-app-name>
flyctl volumes create openclaw_data --region <your-region> --size 1
flyctl secrets set ANTHROPIC_API_KEY=<your-key>
flyctl secrets set TELEGRAM_BOT_TOKEN=<your-token>
flyctl deploy
```

The gateway starts and writes a default config to `/data/openclaw.json`.

## 3. Configure

SSH in to set your model and Telegram user ID, then restart:

```bash
flyctl ssh console
su - node
openclaw config set agents.defaults.model.primary 'anthropic/claude-sonnet-4-6'
openclaw config set channels.telegram.allowFrom '[<your-telegram-id>]'
exit
exit
flyctl machine restart
```

Find your Telegram user ID via [@userinfobot](https://t.me/userinfobot). The `su - node` is required — running `openclaw` as root creates state directories that the gateway cannot write to. Send your bot a DM to verify it responds.

## Version management

The pinned version lives in `fly.toml` under `[build.args]`.

```bash
# Smoke test latest without committing
flyctl deploy --build-arg OPENCLAW_VERSION=latest

# Adopt a new version — update OPENCLAW_VERSION in fly.toml and commit
```
