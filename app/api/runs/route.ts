export const dynamic = "force-dynamic";
export const revalidate = 0;

import { NextResponse } from "next/server";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { loadRuns } from "../../../lib/storage";
import { runBriefing, isLocked } from "../../../lib/runner";

const RATE_MS = 30_000;
const rateFile = () => path.join(process.env.FACTORY_DATA_DIR ?? "./data", ".rate-limit.json");
const rates = new Map<string, number>();

function checkRate(ip: string): boolean {
  const now = Date.now();
  let last = rates.get(ip) ?? 0;
  try {
    const p = rateFile(); if (fs.existsSync(p)) {
      const j = JSON.parse(fs.readFileSync(p,"utf8")); if (j[ip]) last = Math.max(last, j[ip]);
    }
  } catch {}
  if (now - last < RATE_MS) return false;
  rates.set(ip, now);
  try { fs.mkdirSync(path.dirname(rateFile()),{recursive:true}); fs.writeFileSync(rateFile(), JSON.stringify(Object.fromEntries(rates))); } catch {}
  return true;
}

export async function GET(req: Request) {
  const url = new URL(req.url);
  const rawLimit = Number(url.searchParams.get("limit") ?? 50);
  const limit = Number.isFinite(rawLimit) && rawLimit > 0 ? Math.floor(rawLimit) : 50;
  const rawOffset = Number(url.searchParams.get("offset") ?? 0);
  const offset = Number.isFinite(rawOffset) && rawOffset >= 0 ? Math.floor(rawOffset) : 0;
  const all = loadRuns();
  const runs = all.slice(offset, offset + limit);
  return NextResponse.json({ runs, total: all.length });
}

export async function POST(req: Request) {
  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "127.0.0.1";
  if (isLocked()) return NextResponse.json({ error: "already running" }, { status: 409 });
  if (!checkRate(ip)) return NextResponse.json({ error: "rate limited" }, { status: 429 });
  const runId = crypto.randomUUID();
  (async () => { try { await runBriefing(runId); } catch {} })();
  return NextResponse.json({ runId, status: "started" });
}
