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

SSH in to set your Telegram user ID, then restart:

```bash
flyctl ssh console
su node
openclaw config set channels.telegram.allowFrom '[<your-telegram-id>]'
exit
exit
flyctl machine restart
```

Find your Telegram user ID via [@userinfobot](https://t.me/userinfobot). The `su node` is required — running `openclaw` as root creates state directories that the gateway cannot write to. Use `su node` without the dash: `su - node` starts a login shell that drops the container's environment variables.

The default model (`anthropic/claude-sonnet-4-6`) and other agent defaults are pre-configured by the entrypoint on first start.

Send your bot a DM to verify it responds.

## Secrets

All sensitive values (`ANTHROPIC_API_KEY`, `TELEGRAM_BOT_TOKEN`, `TAILSCALE_AUTHKEY`, `BRAVE_API_KEY`) are stored as [Fly.io secrets](https://fly.io/docs/apps/secrets/), not in `openclaw.json` or the image. Fly injects them as environment variables at runtime; OpenClaw reads them directly. Never put API keys in config files.

## Plugins

### Spotify

Gives the agent read/write access to a Spotify playlist — search, recommend, add, and remove tracks via Telegram. See [`plugins/spotify/README.md`](plugins/spotify/README.md) for setup.

## Tailscale networking

When Tailscale is enabled, the gateway binds to `--bind lan` and uses `--tailscale serve` to expose port 3000 on the tailnet. The `--tailscale-reset-on-exit` flag cleans up the Serve config on shutdown. This means:

- The gateway is reachable at `https://<hostname>.<tailnet>.ts.net` on your tailnet
- Fly.io's public proxy is not used — remove `[http_service]` from `fly.toml` (handled by `provision.sh`)
- Access requires being on your tailnet; the public internet has no path to the gateway

Without Tailscale, the gateway binds to `--bind lan` only, reachable within Fly.io's private WireGuard network. Telegram and other outbound channels work fine in either mode.

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
flyctl secrets set BRAVE_API_KEY=<your-key>      # if web search was enabled
flyctl secrets set TAILSCALE_AUTHKEY=<your-key>  # if Tailscale was enabled
```

## Teardown

```bash
./scripts/provision.sh down
```

Destroys the app and its volumes. Prompts for confirmation.

## Model Delegation: Haiku First, Sonnet When Needed

LeanClaw defaults to Haiku for all agent tasks — fast, capable, and cost-effective.

When a task demands deeper reasoning (complex architecture, advanced synthesis, edge cases), Dr. Claw asks for Sonnet escalation. This is a **gated but fluid** pattern:

**Categories needing Sonnet:**
- Complex system design and architecture decisions
- Synthesis across multiple sources with novel analysis
- Creative/strategic work (designing skills, frameworks, roadmaps)
- Edge cases where nuance and judgment matter
- Anything Haiku flags as uncertain

**Request Format:**
The agent flags the category and briefly explains why Haiku isn't sufficient. Example:
> "I need Sonnet for system design. Planning the Tailscale integration requires reasoning about competing concerns (security, cost, topology)."

**Response:** Approve ("yes"), deny ("no"), or no response (assume Haiku is fine).

**After Escalation:** Return to Haiku for follow-up work.

See `workspace/DELEGATION.md` for the full rubric.

## Heartbeat

The heartbeat runs a periodic agent turn to surface anything that needs attention. LeanClaw configures it for minimal ambient cost by default.

### Baseline config (`config/leanclaw-overrides.json`)

```json
"heartbeat": {
  "every": "30m",
  "model": "anthropic/claude-haiku-4-5-20251001",
  "lightContext": true,
  "isolatedSession": true,
  "activeHours": {
    "start": "08:00",
    "end": "23:00",
    "timezone": "America/New_York"
  }
}
```

- **`model: haiku`** — cheap and sufficient for routine signal evaluation
- **`isolatedSession: true`** — each tick runs in a fresh session; no conversation history loaded (~100k → ~2-5k tokens per run)
- **`lightContext: true`** — only `HEARTBEAT.md` is loaded at bootstrap; workspace files are excluded
- **`activeHours`** — no overnight burns; adjust timezone to match your location

### Cost dial: HEARTBEAT.md

`workspace/HEARTBEAT.md` controls what the heartbeat actually does:

| State | Behavior | Cost |
|---|---|---|
| Missing | Heartbeat runs; agent decides what to do | Haiku turn |
| Exists, effectively empty (blank lines / `#` comments only) | OpenClaw skips the run entirely | **Zero** |
| Has checklist content | Heartbeat runs; agent evaluates each item | Haiku turn |

Keep `HEARTBEAT.md` empty until you have integrations worth checking. This is the intended default — the system stays on but costs nothing.

### Scaling up

Add items to `HEARTBEAT.md` incrementally as integrations come online:

```md
# Heartbeat checklist

- Scan inbox for urgent emails
- Check calendar for events in the next 2 hours
```

Each line is a check Haiku evaluates every 30 minutes. If nothing is urgent, it replies `HEARTBEAT_OK` and nothing is delivered to you.

For checks that need more capability (nuanced analysis, complex routing decisions), use a dedicated cron job with a model override instead of the heartbeat:

```bash
openclaw cron add \
  --name "Weekly review" \
  --cron "0 9 * * 1" \
  --tz "America/New_York" \
  --session isolated \
  --message "Review the week's work and surface anything worth following up on." \
  --model opus \
  --announce
```

The pattern: **heartbeat handles ambient awareness cheaply; cron handles scheduled depth**.

## Version management

`OPENCLAW_VERSION` in `fly.toml` is currently set to `latest`. ghcr.io image tags do not reliably match openclaw's reported version numbers — use `openclaw --version` via SSH to identify what's actually running.

```bash
flyctl ssh console --command "openclaw --version"
```

To pin a specific build once a known-good image tag is confirmed, update `OPENCLAW_VERSION` in `fly.toml` and commit.
