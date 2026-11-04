import fs from "node:fs";
import path from "node:path";

export type RunRecord = {
  id: string;
  timestamp: string;
  success: boolean;
  error?: string;
  newItemCount: number;
  itemCount: number;
  isBaseline: boolean;
};

export type Item = { id: string; [k: string]: unknown };

const DATA_DIR = process.env.FACTORY_DATA_DIR ?? "./data";

function dataDir(): string {
  return path.resolve(DATA_DIR);
}

function ensureDir(): void {
  fs.mkdirSync(dataDir(), { recursive: true });
}

function atomicWrite(filePath: string, content: string): void {
  ensureDir();
  const tmp = filePath + ".tmp." + process.pid + "." + Date.now();
  fs.writeFileSync(tmp, content, "utf8");
  fs.renameSync(tmp, filePath);
}

function runsPath(): string {
  return path.join(dataDir(), "runs.jsonl");
}

function itemsPath(runId: string): string {
  // sanitize runId to avoid path traversal
  const safe = runId.replace(/[^a-zA-Z0-9._-]/g, "_");
  return path.join(dataDir(), `items-${safe}.json`);
}

export function saveRun(run: RunRecord): void {
  ensureDir();
  const line = JSON.stringify(run) + "\n";
  fs.appendFileSync(runsPath(), line, "utf8");
}

export function loadRuns(limit?: number): RunRecord[] {
  try {
    const raw = fs.readFileSync(runsPath(), "utf8");
    const lines = raw.split("\n").filter((l) => l.trim().length > 0);
    const records: RunRecord[] = [];
    for (const l of lines) {
      try {
        records.push(JSON.parse(l) as RunRecord);
      } catch {
        // skip corrupt line
      }
    }
    records.sort((a, b) => (a.timestamp < b.timestamp ? 1 : -1));
    return limit ? records.slice(0, limit) : records;
  } catch {
    return [];
  }
}

export function saveItems(items: Item[], runId: string): void {
  atomicWrite(itemsPath(runId), JSON.stringify(items, null, 2));
}

export function loadItems(runId: string): Item[] {
  try {
    const raw = fs.readFileSync(itemsPath(runId), "utf8");
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) return parsed as Item[];
    return [];
  } catch {
    return [];
  }
}

export function getLastSuccessfulRun(): RunRecord | null {
  const runs = loadRuns();
  // most recent successful by timestamp order
  for (const r of runs) {
    if (r.success) return r;
  }
  return null;
}

export function getAllKnownItemIds(): Set<string> {
  const ids = new Set<string>();
  // gather from items files
  try {
    const files = fs.readdirSync(dataDir());
    for (const f of files) {
      if (!f.startsWith("items-") || !f.endsWith(".json")) continue;
      try {
        const raw = fs.readFileSync(path.join(dataDir(), f), "utf8");
        const arr = JSON.parse(raw);
        if (Array.isArray(arr)) {
          for (const it of arr) {
            if (it && typeof it.id === "string") ids.add(it.id);
          }
        }
      } catch {
        // skip
      }
    }
  } catch {
    // dir missing
  }
  return ids;
}