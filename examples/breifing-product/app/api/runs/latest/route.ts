export const dynamic = "force-dynamic";
export const revalidate = 0;

import { NextResponse } from "next/server";
import { getLastSuccessfulRun } from "../../../../lib/storage";

export async function GET() {
  return NextResponse.json(getLastSuccessfulRun());
}
