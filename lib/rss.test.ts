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

const EMPTY = `<rss version="2.0"><channel></channel></rss>`;

function feed(xml: string): string {
  return `<rss version="2.0"><channel>${xml}</channel></rss>`;
}

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
  it("rejects incomplete document", async () => {
    global.fetch = vi.fn().mockResolvedValue({ ok: true, status: 200, text: async () => `<rss version="2.0"><channel><item><title>t</title><link>l</link></item></channel>` });
    const r = await fetchHNFeed();
    expect(r.items).toEqual([]);
    expect(r.error).toBeTruthy();
  });
  it("handles valid empty feed", async () => {
    global.fetch = vi.fn().mockResolvedValue({ ok: true, status: 200, text: async () => EMPTY });
    const r = await fetchHNFeed();
    expect(r).toEqual({ items: [], error: undefined });
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
  it("decodes named and numeric entities", async () => {
    const xml = feed(`<item><title>&amp;lt; &lt; &gt; &quot; &apos; &#38; &#60; &#x26;</title><link>https://example.com/x?a=1&amp;b=2</link></item>`);
    global.fetch = vi.fn().mockResolvedValue({ ok: true, status: 200, text: async () => xml });
    const r = await fetchHNFeed();
    expect(r.items[0].title).toBe("&lt; < > \" ' & < &");
    expect(r.items[0].link).toBe("https://example.com/x?a=1&b=2");
  });
  it("does not double-decode entities", async () => {
    const xml = feed(`<item><title>&amp;lt;</title><link>https://example.com/y?&#38;amp;</link></item>`);
    global.fetch = vi.fn().mockResolvedValue({ ok: true, status: 200, text: async () => xml });
    const r = await fetchHNFeed();
    expect(r.items[0].title).toBe("&lt;");
    expect(r.items[0].link).toBe("https://example.com/y?&amp;");
  });
  it("handles CDATA", async () => {
    const xml = feed(`<item><title><![CDATA[Hello <b>world</b>]]></title><link>https://example.com/cd</link></item>`);
    global.fetch = vi.fn().mockResolvedValue({ ok: true, status: 200, text: async () => xml });
    const r = await fetchHNFeed();
    expect(r.items[0].title).toBe("Hello world");
  });
  it("rejects missing required fields", async () => {
    const xml = feed(`<item><title>   </title><link>https://example.com/z</link></item><item><title>t</title><link>  </link></item>`);
    global.fetch = vi.fn().mockResolvedValue({ ok: true, status: 200, text: async () => xml });
    const r = await fetchHNFeed();
    expect(r.items).toEqual([]);
    expect(r.error).toBeTruthy();
  });
});
