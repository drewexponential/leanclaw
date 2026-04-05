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

const URIS_PARAM = {
  uris: {
    type: "array",
    items: { type: "string" },
    description: 'Spotify item URIs (format: "spotify:track:<id>")',
    minItems: 1,
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
        "Search Spotify for items by keyword, artist name, or vibe description. Returns item names, artists, IDs, and URIs.",
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
            description: "Max results (1–10, default 10)",
            minimum: 1,
            maximum: 10,
          },
        },
      },
      async execute(_id, params) {
        const items = await getClient().search(
          String(params.query),
          typeof params.limit === "number" ? params.limit : 10,
        );
        return json(items);
      },
    });

    api.registerTool({
      name: "spotify_recommend",
      label: "Spotify Recommend",
      description:
        "Get item recommendations based on 1–5 seed item IDs. Use spotify_search first to find seed IDs.",
      parameters: {
        type: "object",
        required: ["seed_ids"],
        additionalProperties: false,
        properties: {
          seed_ids: {
            type: "array",
            items: { type: "string" },
            description: "1–5 Spotify item IDs to seed recommendations",
            minItems: 1,
            maxItems: 5,
          },
          limit: {
            type: "number",
            description: "Max results (1–10, default 10)",
            minimum: 1,
            maximum: 10,
          },
        },
      },
      async execute(_id, params) {
        const items = await getClient().recommend(
          params.seed_ids as string[],
          typeof params.limit === "number" ? params.limit : 10,
        );
        return json(items);
      },
    });

    api.registerTool({
      name: "spotify_get_my_playlists",
      label: "My Playlists",
      description:
        "List all Spotify playlists owned by or visible to the authenticated account. Use this to find a playlist ID before performing playlist operations.",
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
        "Create a new Spotify playlist. Returns the playlist ID and a share URL. Send the URL to the user so they can follow it in their Spotify app.",
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
      name: "spotify_playlist_items_list",
      label: "List Playlist Items",
      description: "List the items currently in a Spotify playlist.",
      parameters: {
        type: "object",
        required: ["playlist_id"],
        additionalProperties: false,
        properties: { ...PLAYLIST_ID_PARAM },
      },
      async execute(_id, params) {
        const items = await getClient().getPlaylistTracks(String(params.playlist_id));
        return json(items);
      },
    });

    api.registerTool({
      name: "spotify_playlist_items_add",
      label: "Add Playlist Items",
      description: "Add one or more items to a Spotify playlist by URI.",
      parameters: {
        type: "object",
        required: ["playlist_id", "uris"],
        additionalProperties: false,
        properties: {
          ...PLAYLIST_ID_PARAM,
          ...URIS_PARAM,
        },
      },
      async execute(_id, params) {
        const uris = params.uris as string[];
        await getClient().addToPlaylist(String(params.playlist_id), uris);
        return json({ added: uris.length, uris });
      },
    });

    api.registerTool({
      name: "spotify_playlist_items_reorder",
      label: "Reorder Playlist Items",
      description:
        "Move one or more items within a Spotify playlist by position. Use spotify_playlist_items_list first to get current positions (0-based index).",
      parameters: {
        type: "object",
        required: ["playlist_id", "range_start", "insert_before"],
        additionalProperties: false,
        properties: {
          ...PLAYLIST_ID_PARAM,
          range_start: {
            type: "number",
            description: "0-based index of the first item to move",
          },
          insert_before: {
            type: "number",
            description: "0-based index of the position to insert the items before",
          },
          range_length: {
            type: "number",
            description: "Number of consecutive items to move (default 1)",
            minimum: 1,
          },
        },
      },
      async execute(_id, params) {
        await getClient().reorderPlaylistItems(
          String(params.playlist_id),
          Number(params.range_start),
          Number(params.insert_before),
          typeof params.range_length === "number" ? params.range_length : 1,
        );
        return json({ reordered: true, range_start: params.range_start, insert_before: params.insert_before });
      },
    });

    api.registerTool({
      name: "spotify_playlist_items_remove",
      label: "Remove Playlist Items",
      description: "Remove one or more items from a Spotify playlist by URI.",
      parameters: {
        type: "object",
        required: ["playlist_id", "uris"],
        additionalProperties: false,
        properties: {
          ...PLAYLIST_ID_PARAM,
          ...URIS_PARAM,
        },
      },
      async execute(_id, params) {
        const uris = params.uris as string[];
        await getClient().removeFromPlaylist(String(params.playlist_id), uris);
        return json({ removed: uris.length, uris });
      },
    });
  },
};

export default plugin;
