export const dynamic = "force-dynamic";
export const revalidate = 0;

import { NextResponse } from "next/server";
import { loadRuns } from "../../../../lib/storage";

export async function GET() {
  const runs = loadRuns(1);
  return NextResponse.json(runs[0] ?? null);
}
