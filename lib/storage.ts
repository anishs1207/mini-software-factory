import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

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

function dataDir(): string {
  // FACTORY_DATA_DIR must point at persistent VM storage across releases so
  // run history and comparison state (known item ids) survive restart/release.
  return path.resolve(process.env.FACTORY_DATA_DIR ?? "./data");
}

function ensureDir(): void {
  fs.mkdirSync(dataDir(), { recursive: true });
}

function atomicWrite(filePath: string, content: string): void {
  ensureDir();
  const tmp = filePath + ".tmp." + process.pid + "." + Date.now() + "." + crypto.randomUUID();
  const fd = fs.openSync(tmp, "w");
  fs.writeSync(fd, Buffer.from(content, "utf8"));
  fs.fsyncSync(fd);
  fs.closeSync(fd);
  fs.renameSync(tmp, filePath);
}

function runsPath(): string {
  return path.join(dataDir(), "runs.jsonl");
}

function itemsPath(runId: string): string {
  const safe = runId.replace(/[^a-zA-Z0-9._-]/g, "_");
  return path.join(dataDir(), `items-${safe}.json`);
}

export function saveRun(run: RunRecord): void {
  ensureDir();
  const line = JSON.stringify(run) + "\n";
  const fd = fs.openSync(runsPath(), "a");
  fs.writeSync(fd, Buffer.from(line, "utf8"));
  fs.fsyncSync(fd);
  fs.closeSync(fd);
}

export class StorageCorruptionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "StorageCorruptionError";
  }
}

function isRunRecord(v: unknown): v is RunRecord {
  if (!v || typeof v !== "object") return false;
  const r = v as Record<string, unknown>;
  return (
    typeof r.id === "string" &&
    typeof r.timestamp === "string" &&
    typeof r.success === "boolean" &&
    typeof r.newItemCount === "number" &&
    Number.isFinite(r.newItemCount) &&
    typeof r.itemCount === "number" &&
    Number.isFinite(r.itemCount) &&
    typeof r.isBaseline === "boolean" &&
    (r.error === undefined || typeof r.error === "string")
  );
}

export function loadRuns(limit?: number): RunRecord[] {
  let raw: string;
  try {
    raw = fs.readFileSync(runsPath(), "utf8");
  } catch (e: any) {
    if (e && e.code === "ENOENT") return [];
    throw e;
  }
  const lines = raw.split("\n").filter((l) => l.trim().length > 0);
  const records: RunRecord[] = [];
  for (const l of lines) {
    let parsed: unknown;
    try {
      parsed = JSON.parse(l);
    } catch {
      throw new StorageCorruptionError("corrupt runs.jsonl line");
    }
    if (!isRunRecord(parsed)) {
      throw new StorageCorruptionError("invalid RunRecord in runs.jsonl");
    }
    records.push(parsed);
  }
  records.sort((a, b) => (a.timestamp < b.timestamp ? 1 : -1));
  return limit ? records.slice(0, limit) : records;
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
  for (const r of runs) {
    if (r.success) return r;
  }
  return null;
}

export function getAllKnownItemIds(): Set<string> {
  const ids = new Set<string>();
  let files: string[];
  try {
    files = fs.readdirSync(dataDir());
  } catch (e: any) {
    if (e && e.code === "ENOENT") return ids;
    throw e;
  }
  for (const f of files) {
    if (!f.startsWith("items-") || !f.endsWith(".json")) continue;
    const raw = fs.readFileSync(path.join(dataDir(), f), "utf8");
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch {
      throw new StorageCorruptionError(`corrupt item file ${f}`);
    }
    if (!Array.isArray(parsed)) {
      throw new StorageCorruptionError(`invalid item file ${f}`);
    }
    for (const it of parsed) {
      if (!it || typeof it !== "object" || typeof (it as any).id !== "string") {
        throw new StorageCorruptionError(`invalid item in ${f}`);
      }
      ids.add((it as any).id);
    }
  }
  return ids;
}