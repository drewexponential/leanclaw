#!/usr/bin/env node
/**
 * One-time Spotify OAuth setup script.
 * Run locally to obtain a refresh token, then store it as a Fly.io secret.
 *
 * Usage:
 *   SPOTIFY_CLIENT_ID=xxx SPOTIFY_CLIENT_SECRET=xxx node scripts/spotify-auth.mjs
 *
 * Prerequisites:
 *   - A Spotify app registered at https://developer.spotify.com/dashboard
 *   - Redirect URI set to: http://localhost:8888/callback
 */

import http from "node:http";
import { exec } from "node:child_process";

const CLIENT_ID = process.env.SPOTIFY_CLIENT_ID;
const CLIENT_SECRET = process.env.SPOTIFY_CLIENT_SECRET;
const REDIRECT_URI = "http://127.0.0.1:8888/callback";
const PORT = 8888;
const SCOPES = [
  "playlist-read-private",
  "playlist-read-collaborative",
  "playlist-modify-public",
  "playlist-modify-private",
].join(" ");

if (!CLIENT_ID || !CLIENT_SECRET) {
  console.error("Error: SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET must be set.");
  console.error("Usage: SPOTIFY_CLIENT_ID=xxx SPOTIFY_CLIENT_SECRET=xxx node scripts/spotify-auth.mjs");
  process.exit(1);
}

const authUrl = new URL("https://accounts.spotify.com/authorize");
authUrl.searchParams.set("client_id", CLIENT_ID);
authUrl.searchParams.set("response_type", "code");
authUrl.searchParams.set("redirect_uri", REDIRECT_URI);
authUrl.searchParams.set("scope", SCOPES);
authUrl.searchParams.set("show_dialog", "true");

console.log("\nOpening browser to authorize Spotify...");
console.log("If it doesn't open automatically, visit:\n");
console.log(" ", authUrl.href, "\n");

exec(`open "${authUrl.href}"`);

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  if (url.pathname !== "/callback") {
    res.writeHead(404);
    res.end();
    return;
  }

  const code = url.searchParams.get("code");
  const error = url.searchParams.get("error");

  if (error || !code) {
    res.end(`Authorization failed: ${error ?? "no code returned"}`);
    server.close();
    process.exit(1);
  }

  const tokenResponse = await fetch("https://accounts.spotify.com/api/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization: `Basic ${Buffer.from(`${CLIENT_ID}:${CLIENT_SECRET}`).toString("base64")}`,
    },
    body: new URLSearchParams({
      grant_type: "authorization_code",
      code,
      redirect_uri: REDIRECT_URI,
    }),
  });

  const data = await tokenResponse.json();

  if (!tokenResponse.ok) {
    res.end(`Token exchange failed: ${JSON.stringify(data)}`);
    server.close();
    process.exit(1);
  }

  res.end("<html><body><h2>Authorization successful — you can close this tab.</h2></body></html>");
  server.close();

  console.log("Authorization successful!\n");
  console.log("Granted scopes:", data.scope, "\n");
  console.log("Store the refresh token as a Fly.io secret:\n");
  console.log(`  fly secrets set SPOTIFY_REFRESH_TOKEN="${data.refresh_token}"\n`);
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`Waiting for callback on http://127.0.0.1:${PORT}/callback ...`);
});
