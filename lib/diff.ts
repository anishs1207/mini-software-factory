import type { RSSItem } from "./rss";

export type Item = RSSItem;

export function computeNewItems(currentItems: Item[], knownIds: Set<string>): Item[] {
  return currentItems.filter((item) => !knownIds.has(item.id));
}

export function isFirstRun(knownIds: Set<string>): boolean {
  return knownIds.size === 0;
}

export function withBaseline(currentItems: Item[], knownIds: Set<string>): {
  newItems: Item[];
  isBaseline: boolean;
} {
  const isBaseline = isFirstRun(knownIds);
  return { newItems: computeNewItems(currentItems, knownIds), isBaseline };
}
