import type { RSSItem } from "./rss";

export type Item = RSSItem;

export function computeNewItems(currentItems: Item[], knownIds: Set<string>): Item[] {
  const seen = new Set<string>();
  const out: Item[] = [];
  for (const item of currentItems) {
    if (!item.id) continue;
    if (seen.has(item.id)) continue;
    seen.add(item.id);
    if (knownIds.has(item.id)) continue;
    out.push(item);
  }
  return out;
}

export function isFirstRun(hasSuccessfulRuns: boolean): boolean;
export function isFirstRun(knownIds: Set<string>): boolean;
export function isFirstRun(arg: boolean | Set<string>): boolean {
  if (arg instanceof Set) return arg.size === 0;
  return !arg;
}

export function withBaseline(currentItems: Item[], knownIds: Set<string>, hasSuccessfulRuns?: boolean): {
  newItems: Item[];
  isBaseline: boolean;
} {
  const isBaseline = hasSuccessfulRuns === undefined ? knownIds.size === 0 : !hasSuccessfulRuns;
  return { newItems: computeNewItems(currentItems, knownIds), isBaseline };
}
