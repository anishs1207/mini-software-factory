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