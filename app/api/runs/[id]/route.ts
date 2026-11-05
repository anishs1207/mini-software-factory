export const dynamic = "force-dynamic";
export const revalidate = 0;

import { NextResponse } from "next/server";
import { loadRuns } from "../../../../lib/storage";
import { isLocked } from "../../../../lib/runner";

export async function GET(_req: Request, { params }: { params: { id: string } }) {
  const runs = loadRuns();
  const run = runs.find((r) => r.id === params.id);
  if (run) {
    return NextResponse.json({ id: run.id, status: "completed", run });
  }
  if (isLocked()) {
    return NextResponse.json({ id: params.id, status: "running" });
  }
  return NextResponse.json({ id: params.id, status: "pending" }, { status: 404 });
}
