import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import * as S from "../lib/storage";

function tmpDir() {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), "storage-"));
  process.env.FACTORY_DATA_DIR = d;
  return d;
}

test("save/load runs persists", () => {
  const d = tmpDir();
  const r = { id: "1", timestamp: new Date().toISOString(), success: true, newItemCount: 2, itemCount: 5, isBaseline: true };
  S.saveRun(r);
  const runs = S.loadRuns();
  assert.equal(runs.length, 1);
  assert.equal(runs[0].id, "1");
  // new process env already same; reload by re-import not needed
  delete process.env.FACTORY_DATA_DIR;
  fs.rmSync(d, { recursive: true, force: true });
});

test("last successful run", () => {
  const d = tmpDir();
  S.saveRun({ id: "a", timestamp: "2020-01-01T00:00:00.000Z", success: false, newItemCount: 0, itemCount: 0, isBaseline: false });
  S.saveRun({ id: "b", timestamp: "2020-01-02T00:00:00.000Z", success: true, newItemCount: 1, itemCount: 1, isBaseline: false });
  const last = S.getLastSuccessfulRun();
  assert.equal(last?.id, "b");
  delete process.env.FACTORY_DATA_DIR;
  fs.rmSync(d, { recursive: true, force: true });
});

test("getAllKnownItemIds accumulates", () => {
  const d = tmpDir();
  S.saveItems([{ id: "x" }, { id: "y" }], "r1");
  S.saveItems([{ id: "y" }, { id: "z" }], "r2");
  const ids = S.getAllKnownItemIds();
  assert.deepEqual([...ids].sort(), ["x", "y", "z"]);
  delete process.env.FACTORY_DATA_DIR;
  fs.rmSync(d, { recursive: true, force: true });
});

test("missing/corrupt files handled", () => {
  const d = tmpDir();
  assert.deepEqual(S.loadRuns(), []);
  assert.deepEqual(S.loadItems("nope"), []);
  assert.equal(S.getLastSuccessfulRun(), null);
  // corrupt runs line
  fs.writeFileSync(path.join(d, "runs.jsonl"), "{bad json}\n", "utf8");
  assert.throws(() => S.loadRuns());
  delete process.env.FACTORY_DATA_DIR;
  fs.rmSync(d, { recursive: true, force: true });
});

test("loadRuns rejects malformed RunRecord values", () => {
  const d = tmpDir();
  const valid = { id: "1", timestamp: "2020-01-01T00:00:00.000Z", success: true, newItemCount: 2, itemCount: 5, isBaseline: true };
  const cases: Array<Record<string, unknown>> = [
    { ...valid, id: 1 },
    { ...valid, timestamp: 2 },
    { ...valid, success: "true" },
    { ...valid, newItemCount: "2" },
    { ...valid, itemCount: false },
    { ...valid, isBaseline: "false" },
    { ...valid, error: 42 },
    { id: "1", timestamp: "t", success: true, newItemCount: 2, itemCount: 5 }
  ];
  for (const c of cases) {
    fs.writeFileSync(path.join(d, "runs.jsonl"), JSON.stringify(c) + "\n", "utf8");
    assert.throws(() => S.loadRuns(), (err) => err instanceof S.StorageCorruptionError);
  }
  fs.writeFileSync(path.join(d, "runs.jsonl"), '{"id":"1","timestamp":"t","success":true,"newItemCount":1e999,"itemCount":5,"isBaseline":true}\n', "utf8");
  assert.throws(() => S.loadRuns(), (err) => err instanceof S.StorageCorruptionError);
  fs.writeFileSync(path.join(d, "runs.jsonl"), '{"id":"1","timestamp":"t","success":true,"newItemCount":2,"itemCount":1e999,"isBaseline":true}\n', "utf8");
  assert.throws(() => S.loadRuns(), (err) => err instanceof S.StorageCorruptionError);
  const corrupt = "{bad json}\n";
  fs.writeFileSync(path.join(d, "runs.jsonl"), corrupt, "utf8");
  assert.throws(() => S.loadRuns(), (err) => err instanceof S.StorageCorruptionError);
  assert.equal(fs.readFileSync(path.join(d, "runs.jsonl"), "utf8"), corrupt);
  delete process.env.FACTORY_DATA_DIR;
  fs.rmSync(d, { recursive: true, force: true });
});

test("getAllKnownItemIds throws on corrupt or non-array item files", () => {
  const d = tmpDir();
  S.saveItems([{ id: "x" }], "r1");
  const corruptPath = path.join(d, "items-r2.json");
  const corrupt = "{bad json}\n";
  fs.writeFileSync(corruptPath, corrupt, "utf8");
  assert.throws(() => S.getAllKnownItemIds(), (err) => err instanceof S.StorageCorruptionError);
  assert.equal(fs.readFileSync(corruptPath, "utf8"), corrupt);
  const nonArrayPath = path.join(d, "items-r3.json");
  fs.writeFileSync(nonArrayPath, JSON.stringify({ id: "y" }), "utf8");
  assert.throws(() => S.getAllKnownItemIds(), (err) => err instanceof S.StorageCorruptionError);
  const unreadablePath = path.join(d, "items-r4.json");
  fs.mkdirSync(unreadablePath);
  assert.throws(() => S.getAllKnownItemIds());
  fs.rmSync(unreadablePath, { recursive: true, force: true });
  const fileRoot = path.join(os.tmpdir(), "storage-root-" + Date.now());
  fs.writeFileSync(fileRoot, "x", "utf8");
  const old = process.env.FACTORY_DATA_DIR;
  process.env.FACTORY_DATA_DIR = fileRoot;
  assert.throws(() => S.getAllKnownItemIds());
  process.env.FACTORY_DATA_DIR = old;
  fs.rmSync(fileRoot, { force: true });
  fs.rmSync(corruptPath, { force: true });
  fs.rmSync(nonArrayPath, { force: true });
  const ids = S.getAllKnownItemIds();
  assert.deepEqual([...ids].sort(), ["x"]);
  delete process.env.FACTORY_DATA_DIR;
  fs.rmSync(d, { recursive: true, force: true });
});
