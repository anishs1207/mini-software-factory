import { describe, it, expect, vi } from "vitest";
import { fetchHNFeed } from "./rss";

const SAMPLE = `<?xml version="1.0"?>
<rss version="2.0"><channel><title>Hacker News</title>
<item>
  <title>Story One</title>
  <link>https://example.com/1</link>
  <pubDate>Wed, 04 Nov 2026 09:00:00 +0000</pubDate>
  <guid>123</guid>
</item>
<item>
  <title>Story Two</title>
  <link>https://example.com/2</link>
  <pubDate>Wed, 04 Nov 2026 08:00:00 +0000</pubDate>
</item>
</channel></rss>`;

describe("fetchHNFeed", () => {
  it("parses items", async () => {
    global.fetch = vi.fn().mockResolvedValue({ ok: true, status: 200, text: async () => SAMPLE });
    const r = await fetchHNFeed();
    expect(r.error).toBeUndefined();
    expect(r.items.length).toBe(2);
    expect(r.items[0].id).toBe("123");
    expect(r.items[1].id).toHaveLength(64);
  });
  it("handles invalid xml", async () => {
    global.fetch = vi.fn().mockResolvedValue({ ok: true, status: 200, text: async () => "not xml" });
    const r = await fetchHNFeed();
    expect(r.items).toEqual([]);
    expect(r.error).toBeTruthy();
  });
  it("handles empty response", async () => {
    global.fetch = vi.fn().mockResolvedValue({ ok: true, status: 200, text: async () => "" });
    const r = await fetchHNFeed();
    expect(r.error).toBe("Empty response");
  });
  it("handles timeout", async () => {
    global.fetch = vi.fn().mockImplementation(() => new Promise((_, rej) => {
      const e = new Error("aborted"); e.name = "AbortError"; setTimeout(() => rej(e), 0);
    }));
    const r = await fetchHNFeed();
    expect(r.error).toBe("Network timeout");
  });
});
