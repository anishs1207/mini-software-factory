import type { RunRecord } from "./storage";
import type { RSSItem } from "./rss";

export type Run = RunRecord;
export type BriefingItem = RSSItem;

export type RunHistoryResponse = { runs: Run[]; total: number };
export type LatestResponse = Run | null;

export type NewItem = BriefingItem;
