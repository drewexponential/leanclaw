interface Track {
  id: string;
  uri: string;
  name: string;
  artist: string;
}

export interface PlaylistTrack extends Track {
  addedAt: string;
}

interface SpotifyTrackObject {
  id: string;
  uri: string;
  name: string;
  artists: Array<{ name: string }>;
}

interface SpotifyPlaylistItem {
  item: SpotifyTrackObject | null;
  added_at: string;
}

function normalizeTrack(t: SpotifyTrackObject): Track {
  return {
    id: t.id,
    uri: t.uri,
    name: t.name,
    artist: t.artists.map((a) => a.name).join(", "),
  };
}

export class SpotifyClient {
  private readonly clientId: string;
  private readonly clientSecret: string;
  private readonly refreshToken: string;
  private accessToken: string | null = null;
  private tokenExpiresAt = 0;

  constructor() {
    const { SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET, SPOTIFY_REFRESH_TOKEN } = process.env;
    if (!SPOTIFY_CLIENT_ID || !SPOTIFY_CLIENT_SECRET || !SPOTIFY_REFRESH_TOKEN) {
      throw new Error(
        "SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET, and SPOTIFY_REFRESH_TOKEN must be set",
      );
    }
    this.clientId = SPOTIFY_CLIENT_ID;
    this.clientSecret = SPOTIFY_CLIENT_SECRET;
    this.refreshToken = SPOTIFY_REFRESH_TOKEN;
  }

  private async getAccessToken(): Promise<string> {
    if (this.accessToken && Date.now() < this.tokenExpiresAt - 60_000) {
      return this.accessToken;
    }
    const response = await fetch("https://accounts.spotify.com/api/token", {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Authorization: `Basic ${Buffer.from(`${this.clientId}:${this.clientSecret}`).toString("base64")}`,
      },
      body: new URLSearchParams({
        grant_type: "refresh_token",
        refresh_token: this.refreshToken,
      }),
    });
    if (!response.ok) {
      throw new Error(`Spotify token refresh failed: ${response.status}`);
    }
    const data = (await response.json()) as { access_token: string; expires_in: number };
    this.accessToken = data.access_token;
    this.tokenExpiresAt = Date.now() + data.expires_in * 1000;
    return this.accessToken;
  }

  private async request<T>(path: string, options: RequestInit = {}): Promise<T> {
    const token = await this.getAccessToken();
    const response = await fetch(`https://api.spotify.com/v1${path}`, {
      ...options,
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        ...(options.headers ?? {}),
      },
    });
    if (!response.ok) {
      const body = await response.text();
      throw new Error(`Spotify API error ${response.status}: ${body}`);
    }
    if (response.status === 204) return undefined as T;
    return response.json() as Promise<T>;
  }

  async search(query: string, limit = 10): Promise<Track[]> {
    const params = new URLSearchParams({ q: query, type: "track", limit: String(limit) });
    const data = await this.request<{ tracks: { items: SpotifyTrackObject[] } }>(
      `/search?${params}`,
    );
    return data.tracks.items.map(normalizeTrack);
  }

  async recommend(seedTrackIds: string[], limit = 10): Promise<Track[]> {
    const params = new URLSearchParams({
      seed_tracks: seedTrackIds.slice(0, 5).join(","),
      limit: String(limit),
    });
    const data = await this.request<{ tracks: SpotifyTrackObject[] }>(
      `/recommendations?${params}`,
    );
    return data.tracks.map(normalizeTrack);
  }

  async getPlaylistTracks(playlistId: string): Promise<PlaylistTrack[]> {
    const data = await this.request<{ items: SpotifyPlaylistItem[] }>(
      `/playlists/${playlistId}/items?limit=10`,
    );
    return data.items
      .filter((item) => item.item)
      .map((item) => ({ ...normalizeTrack(item.item!), addedAt: item.added_at }));
  }

  async addToPlaylist(playlistId: string, trackUris: string[]): Promise<void> {
    for (let i = 0; i < trackUris.length; i += 100) {
      await this.request(`/playlists/${playlistId}/items`, {
        method: "POST",
        body: JSON.stringify({ uris: trackUris.slice(i, i + 100) }),
      });
    }
  }

  async removeFromPlaylist(playlistId: string, trackUris: string[]): Promise<void> {
    await this.request(`/playlists/${playlistId}/items`, {
      method: "DELETE",
      body: JSON.stringify({ items: trackUris.map((uri) => ({ uri })) }),
    });
  }

  async reorderPlaylistItems(
    playlistId: string,
    rangeStart: number,
    insertBefore: number,
    rangeLength = 1,
  ): Promise<void> {
    await this.request(`/playlists/${playlistId}/items`, {
      method: "PUT",
      body: JSON.stringify({ range_start: rangeStart, insert_before: insertBefore, range_length: rangeLength }),
    });
  }

  async getMyPlaylists(): Promise<Array<{ id: string; name: string; url: string; tracks: number }>> {
    const data = await this.request<{
      items: Array<{
        id: string;
        name: string;
        external_urls: { spotify: string };
        tracks: { total: number };
      }>;
    }>("/me/playlists?limit=50");
    return data.items.map((p) => ({
      id: p.id,
      name: p.name,
      url: p.external_urls.spotify,
      tracks: p.tracks?.total ?? 0,
    }));
  }

  async createPlaylist(name: string, description = ""): Promise<{ id: string; url: string }> {
    const data = await this.request<{ id: string; external_urls: { spotify: string } }>(
      "/me/playlists",
      {
        method: "POST",
        body: JSON.stringify({ name, description, public: true, collaborative: false }),
      },
    );
    return { id: data.id, url: data.external_urls.spotify };
  }
}
