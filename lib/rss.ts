export type RSSItem = {
  id: string;
  title: string;
  link: string;
  pubDate: string;
  guid?: string;
};

export type RSSResult = {
  items: RSSItem[];
  error?: string;
};

const FEED_URL = "https://news.ycombinator.com/rss";
const TIMEOUT_MS = 10_000;

import { createHash } from "node:crypto";

function hashLink(link: string): string {
  return createHash("sha256").update(link).digest("hex");
}

function decodeEntities(s: string): string {
  return s
    .replace(/&#x([0-9a-fA-F]+);/g, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(parseInt(d, 10)))
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'");
}

function getTag(xml: string, tag: string): string {
  const re = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`, "i");
  const m = xml.match(re);
  if (!m) return "";
  const inner = m[1]
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/<[^>]+>/g, "");
  return decodeEntities(inner).trim();
}

function isWellFormedXml(text: string): boolean {
  // Reject documents with XML declaration issues etc. Use a simple tag-balance check.
  // Remove CDATA sections, comments, and processing instructions.
  const cleaned = text
    .replace(/<!\[CDATA\[[\s\S]*?\]\]>/g, "")
    .replace(/<!--[^>]*?-->/g, "")
    .replace(/<\?[^>]*?\?>/g, "");
  // Find all tags.
  const tagRegex = /<\/?([A-Za-z][A-Za-z0-9:_-]*)\b[^>]*?>/g;
  const stack: string[] = [];
  let m: RegExpExecArray | null;
  let hasRoot = false;
  let root: string | null = null;
  while ((m = tagRegex.exec(cleaned)) !== null) {
    const full = m[0];
    const name = m[1];
    if (full.startsWith("</")) {
      if (stack.length === 0 || stack[stack.length - 1] !== name) return false;
      stack.pop();
    } else if (!full.endsWith("/>")) {
      stack.push(name);
      if (root === null) { root = name; hasRoot = true; }
    }
  }
  if (stack.length !== 0) return false;
  if (!hasRoot || (root !== "rss" && root !== "feed")) return false;
  return true;
}

function parseItems(xml: string): RSSItem[] {
  const items: RSSItem[] = [];
  const itemRegex = /<item\b[^>]*>([\s\S]*?)<\/item>/gi;
  let match: RegExpExecArray | null;
  while ((match = itemRegex.exec(xml)) !== null) {
    const block = match[1];
    const title = getTag(block, "title");
    const link = getTag(block, "link");
    if (!title || !link) {
      throw new Error("Item missing required title or link");
    }
    const pubDate = getTag(block, "pubDate");
    const guid = getTag(block, "guid") || undefined;
    const id = guid ? guid : hashLink(link);
    items.push({ id, title, link, pubDate, guid });
  }
  return items;
}

export async function fetchHNFeed(): Promise<RSSResult> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(FEED_URL, {
      headers: {
        "User-Agent": "confer-briefing/1.0 (+https://github.com/anishs1207/confer-assignment)",
        Accept: "application/rss+xml, application/xml;q=0.9, */*;q=0.8",
      },
      signal: controller.signal,
    });
    if (!res.ok) {
      return { items: [], error: `HTTP ${res.status}` };
    }
    const text = await res.text();
    if (!text.trim()) {
      return { items: [], error: "Empty response" };
    }
    try {
      // Basic well-formedness check.
      if (!isWellFormedXml(text)) {
        return { items: [], error: "Invalid XML" };
      }
      const items = parseItems(text);
      return { items };
    } catch (e) {
      return { items: [], error: e instanceof Error ? e.message : String(e) };
    }
  } catch (e) {
    if (e instanceof Error && e.name === "AbortError") {
      return { items: [], error: "Network timeout" };
    }
    return { items: [], error: e instanceof Error ? e.message : String(e) };
  } finally {
    clearTimeout(timer);
  }
}
