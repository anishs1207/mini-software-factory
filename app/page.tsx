"use client";
import { useEffect, useState } from "react";

import type { Run, BriefingItem } from "../lib/types";

const RATE_MS = 30000;

export default function Page() {
  const [runs, setRuns] = useState<Run[]>([]);
  const [latest, setLatest] = useState<Run | null>(null);
  const [newItems, setNewItems] = useState<BriefingItem[]>([]);
  const [running, setRunning] = useState(false);
  const [lastRunAt, setLastRunAt] = useState(0);

  async function refresh() {
    const [r, l] = await Promise.all([fetch("/api/runs").then((x) => x.json()), fetch("/api/runs/latest").then((x) => x.json())]);
    setRuns(r.runs ?? []);
    setLatest(l ?? null);
    // fetch items for latest
    if (l?.id) {
      try {
        const res = await fetch(`/api/runs/${l.id}/items`);
        if (res.ok) { const d = await res.json(); setNewItems(d.items ?? []); }
      } catch {}
    }
  }

  useEffect(() => { refresh(); const t = setInterval(refresh, 5000); return () => clearInterval(t); }, []);

  async function runNow() {
    if (Date.now() - lastRunAt < RATE_MS) return;
    if (running) return;
    setRunning(true);
    setLastRunAt(Date.now());
    await fetch("/api/runs", { method: "POST" });
    setTimeout(() => { setRunning(false); refresh(); }, 2000);
  }

  const disabled = running || Date.now() - lastRunAt < RATE_MS;

  return (
    <main style={{ maxWidth: 800, margin: "0 auto", padding: 24, fontFamily: "system-ui, sans-serif" }}>
      <h1>Confer Briefing</h1>
      <section>
        <h2>Latest Briefing</h2>
        {latest ? (
          <>
            <p>{new Date(latest.timestamp).toLocaleDateString()} · {latest.isBaseline ? "Baseline run - all items new" : `${latest.newItemCount} new since last run`}</p>
            <ul>
              {newItems.map((it) => <li key={it.id}><a href={it.link} target="_blank" rel="noreferrer">{it.title}</a></li>)}
            </ul>
          </>
        ) : <p>No runs yet.</p>}
      </section>
      <button onClick={runNow} disabled={disabled} style={{ margin: "12px 0" }}>{running ? "Running..." : "Run Now"}</button>
      <section>
        <h2>Run History</h2>
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead><tr><th>Time</th><th>Status</th><th>New Items</th><th>Error</th></tr></thead>
          <tbody>
            {runs.map((r) => (
              <tr key={r.id}>
                <td>{new Date(r.timestamp).toLocaleString()}</td>
                <td>{r.success ? "✓" : "✗"}</td>
                <td>{r.newItemCount}</td>
                <td>{r.error ?? ""}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>
    </main>
  );
}
