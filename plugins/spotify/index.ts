import type { OpenClawPluginApi } from "openclaw/plugin-sdk/core";
import { SpotifyClient } from "./spotify-client.js";

let client: SpotifyClient | null = null;

function getClient(): SpotifyClient {
  if (!client) client = new SpotifyClient();
  return client;
}

function json(data: unknown) {
  return {
    content: [{ type: "text" as const, text: JSON.stringify(data, null, 2) }],
    details: data,
  };
}

const PLAYLIST_ID_PARAM = {
  playlist_id: {
    type: "string",
    description: "Spotify playlist ID — use spotify_get_my_playlists to find it",
  },
};

const plugin = {
  id: "spotify",
  name: "Spotify",
  description: "Manage Spotify playlists via AI",
  configSchema: { type: "object", additionalProperties: false, properties: {} },

  register(api: OpenClawPluginApi) {
    api.registerTool({
      name: "spotify_search",
      label: "Spotify Search",
      description:
        "Search Spotify for tracks by keyword, artist name, or vibe description. Returns track names, artists, IDs, and URIs.",
      parameters: {
        type: "object",
        required: ["query"],
        additionalProperties: false,
        properties: {
          query: {
            type: "string",
            description: "Search query — keywords, artist name, mood, or vibe",
          },
          limit: {
            type: "number",
            description: "Max results (1–20, default 10)",
            minimum: 1,
            maximum: 20,
          },
        },
      },
      async execute(_id, params) {
        const tracks = await getClient().search(
          String(params.query),
          typeof params.limit === "number" ? params.limit : 10,
        );
        return json(tracks);
      },
    });

    api.registerTool({
      name: "spotify_recommend",
      label: "Spotify Recommend",
      description:
        "Get track recommendations based on 1–5 seed track IDs. Use spotify_search first to find seed IDs.",
      parameters: {
        type: "object",
        required: ["seed_track_ids"],
        additionalProperties: false,
        properties: {
          seed_track_ids: {
            type: "array",
            items: { type: "string" },
            description: "1–5 Spotify track IDs to seed recommendations",
            minItems: 1,
            maxItems: 5,
          },
          limit: {
            type: "number",
            description: "Max results (1–20, default 10)",
            minimum: 1,
            maximum: 20,
          },
        },
      },
      async execute(_id, params) {
        const tracks = await getClient().recommend(
          params.seed_track_ids as string[],
          typeof params.limit === "number" ? params.limit : 10,
        );
        return json(tracks);
      },
    });

    api.registerTool({
      name: "spotify_get_my_playlists",
      label: "My Playlists",
      description: "List all Spotify playlists owned by or visible to the authenticated account. Use this to find a playlist ID before performing playlist operations.",
      parameters: {
        type: "object",
        additionalProperties: false,
        properties: {},
      },
      async execute(_id, _params) {
        const playlists = await getClient().getMyPlaylists();
        return json(playlists);
      },
    });

    api.registerTool({
      name: "spotify_playlist_create",
      label: "Create Playlist",
      description:
        "Create a new collaborative Spotify playlist. Returns the playlist ID and a share URL. Send the URL to the user so they can follow it in their Spotify app.",
      parameters: {
        type: "object",
        required: ["name"],
        additionalProperties: false,
        properties: {
          name: { type: "string", description: "Name for the new playlist" },
          description: { type: "string", description: "Optional playlist description" },
        },
      },
      async execute(_id, params) {
        const playlist = await getClient().createPlaylist(
          String(params.name),
          typeof params.description === "string" ? params.description : "",
        );
        return json(playlist);
      },
    });

    api.registerTool({
      name: "spotify_playlist_list",
      label: "Spotify Playlist",
      description: "List the tracks currently in a Spotify playlist.",
      parameters: {
        type: "object",
        required: ["playlist_id"],
        additionalProperties: false,
        properties: { ...PLAYLIST_ID_PARAM },
      },
      async execute(_id, params) {
        const tracks = await getClient().getPlaylistTracks(String(params.playlist_id));
        return json(tracks);
      },
    });

    api.registerTool({
      name: "spotify_playlist_add",
      label: "Add to Playlist",
      description: "Add one or more tracks to a Spotify playlist by URI.",
      parameters: {
        type: "object",
        required: ["playlist_id", "track_uris"],
        additionalProperties: false,
        properties: {
          ...PLAYLIST_ID_PARAM,
          track_uris: {
            type: "array",
            items: { type: "string" },
            description: 'Spotify track URIs to add (format: "spotify:track:<id>")',
            minItems: 1,
          },
        },
      },
      async execute(_id, params) {
        const uris = params.track_uris as string[];
        await getClient().addToPlaylist(String(params.playlist_id), uris);
        return json({ added: uris.length, uris });
      },
    });

    api.registerTool({
      name: "spotify_playlist_remove",
      label: "Remove from Playlist",
      description: "Remove one or more tracks from a Spotify playlist by URI.",
      parameters: {
        type: "object",
        required: ["playlist_id", "track_uris"],
        additionalProperties: false,
        properties: {
          ...PLAYLIST_ID_PARAM,
          track_uris: {
            type: "array",
            items: { type: "string" },
            description: 'Spotify track URIs to remove (format: "spotify:track:<id>")',
            minItems: 1,
          },
        },
      },
      async execute(_id, params) {
        const uris = params.track_uris as string[];
        await getClient().removeFromPlaylist(String(params.playlist_id), uris);
        return json({ removed: uris.length, uris });
      },
    });
  },
};

export default plugin;
