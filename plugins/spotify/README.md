# Spotify Plugin

Gives the openclaw agent full read/write access to Spotify playlists. Interact with it via Telegram in natural language.

## What you can do

- **List your playlists** — "What Spotify playlists do I have?"
- **Create a playlist** — "Create a new playlist called Vibes"
- **Search** — "Find me some songs by Khruangbin"
- **Recommend** — "Recommend something like Bon Iver"
- **Add** — "Add 5 chill tracks to my playlist"
- **Remove** — "Remove anything by Drake from my playlist"
- **Chain** — "Add 3 songs similar to the last track I added"

The agent calls `spotify_get_my_playlists` to locate playlists by name, then chains `spotify_search` → `spotify_recommend` → `spotify_playlist_add` as needed.

## Prerequisites

- A [Spotify account](https://spotify.com)
- A Spotify app registered at [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard)
  - Set one redirect URI: `http://127.0.0.1:8888/callback`
  - Note the **Client ID** and **Client Secret**

## Setup

### 1. Generate a refresh token

Run the OAuth helper locally (requires Node.js 22+):

```bash
SPOTIFY_CLIENT_ID=xxx SPOTIFY_CLIENT_SECRET=xxx node scripts/spotify-auth.mjs
```

A browser window will open to Spotify's authorization page. Confirm the granted scopes printed by the script include all three: `playlist-read-private playlist-modify-private playlist-modify-public`. After you approve, run the printed `fly secrets set` command.

### 2. Set all three secrets

```bash
fly secrets set \
  SPOTIFY_CLIENT_ID=xxx \
  SPOTIFY_CLIENT_SECRET=xxx \
  SPOTIFY_REFRESH_TOKEN=xxx
```

### 3. Deploy

```bash
fly deploy
```

### 4. Create and share a playlist

Ask the agent via Telegram to create a playlist. It will return a share URL — open it in Spotify to follow the playlist so it appears in your library.

> "Create a new collaborative playlist called Road Trip"

## How it works

The plugin is baked into the Docker image at `/opt/plugins/spotify` and loaded via `plugins.load.paths` in `config/leanclaw-base.json`.

At runtime, the plugin reads credentials from environment variables. Spotify access tokens expire every hour — the client transparently refreshes them using the stored refresh token before each API call, so no user interaction is ever needed after initial setup.

Playlists are created as **public**, so anyone with the share URL can follow and listen. Only the agent can add or remove tracks.

## Registered tools

| Tool | Description |
|---|---|
| `spotify_search` | Keyword or vibe search → ranked track list with IDs and URIs |
| `spotify_recommend` | Seed track IDs → recommended tracks |
| `spotify_get_my_playlists` | List all playlists visible to the authenticated account |
| `spotify_playlist_create` | Create a new collaborative playlist, returns ID and share URL |
| `spotify_playlist_list` | List tracks in a playlist by ID |
| `spotify_playlist_add` | Add tracks by URI |
| `spotify_playlist_remove` | Remove tracks by URI |

## Re-setup after a restore

Secrets are not included in openclaw backups. After restoring from backup, re-set all three secrets and redeploy:

```bash
fly secrets set \
  SPOTIFY_CLIENT_ID=xxx \
  SPOTIFY_CLIENT_SECRET=xxx \
  SPOTIFY_REFRESH_TOKEN=xxx
fly deploy
```

If your Spotify refresh token has expired (rare, but possible after long disuse), re-run `scripts/spotify-auth.mjs` to generate a new one.
