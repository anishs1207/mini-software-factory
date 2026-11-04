import { NextResponse } from "next/server";
import { loadItems } from "../../../../../lib/storage";

export async function GET(_req: Request, { params }: { params: { id: string } }) {
  return NextResponse.json({ items: loadItems(params.id) });
}
