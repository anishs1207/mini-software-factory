import { NextResponse } from "next/server";
import { loadItems, loadRuns } from "../../../../../lib/storage";
import type { Item } from "../../../../../lib/storage";

export async function GET(_req: Request, { params }: { params: { id: string } }) {
  const runId = params.id;
  const current = loadItems(runId);
  const runs = loadRuns();
  const target = runs.find((r) => r.id === runId);
  const earlier = runs.filter((r) => target && r.timestamp < target.timestamp);
  const knownIds = new Set<string>();
  for (const r of earlier) {
    for (const it of loadItems(r.id)) {
      if (it && typeof it.id === "string") knownIds.add(it.id);
    }
  }
  return NextResponse.json({ items: current.filter((it: Item) => !knownIds.has(it.id)) });
}
