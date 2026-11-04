import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import type { RunRecord } from "./storage";
import { saveRun, saveItems, getAllKnownItemIds } from "./storage";
import { fetchHNFeed } from "./rss";
import { withBaseline } from "./diff";

function dataDir(): string { return path.resolve(process.env.FACTORY_DATA_DIR ?? "./data"); }
function lockPath(): string { return path.join(dataDir(), ".run-lock"); }

function acquireLock(): boolean {
  fs.mkdirSync(dataDir(), { recursive: true });
  try {
    fs.writeFileSync(lockPath(), String(process.pid), { flag: "wx" });
    return true;
  } catch {
    return false;
  }
}

function releaseLock(): void {
  try { fs.unlinkSync(lockPath()); } catch {}
}

export async function runBriefing(runId?: string): Promise<RunRecord> {
  if (!acquireLock()) {
    throw new Error("already running");
  }
  const id = runId ?? crypto.randomUUID();
  const timestamp = new Date().toISOString();
  const run: RunRecord = { id, timestamp, success: false, newItemCount: 0, itemCount: 0, isBaseline: false };
  try {
    const feed = await fetchHNFeed();
    if (feed.error) {
      run.success = false; run.error = feed.error;
    } else {
      const known = getAllKnownItemIds();
      const { newItems, isBaseline } = withBaseline(feed.items, known);
      run.newItemCount = newItems.length;
      run.itemCount = feed.items.length;
      run.isBaseline = isBaseline;
      saveItems(feed.items, id);
      run.success = true;
    }
  } catch (e) {
    run.success = false; run.error = e instanceof Error ? e.message : String(e);
  } finally {
    saveRun(run);
    releaseLock();
  }
  return run;
}

export function isLocked(): boolean {
  return fs.existsSync(lockPath());
}
