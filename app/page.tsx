"use client";
import { useCallback, useEffect, useState } from "react";

import type { Run, BriefingItem } from "../lib/types";

const RATE_MS = 30000;
const PAGE_SIZE = 20;
const POLL_INTERVAL = 1500;
const POLL_TIMEOUT = 120000;

export default function Page() {
  const [runs, setRuns] = useState<Run[]>([]);
  const [total, setTotal] = useState(0);
  const [latest, setLatest] = useState<Run | null>(null);
  const [newItems, setNewItems] = useState<BriefingItem[]>([]);
  const [running, setRunning] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [lastRunAt, setLastRunAt] = useState(0);
  const [loadingMore, setLoadingMore] = useState(false);
  const [statusMsg, setStatusMsg] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [rRes, lRes] = await Promise.all([
        fetch(`/api/runs?limit=${PAGE_SIZE}&offset=0`),
        fetch("/api/runs/latest"),
      ]);
      if (!rRes.ok || !lRes.ok) throw new Error("Failed to load briefing data");
      const rData = await rRes.json();
      const lData = (await lRes.json()) ?? null;
      setRuns(rData.runs ?? []);
      setTotal(rData.total ?? 0);
      setLatest(lData);
      if (lData?.id) {
        const res = await fetch(`/api/runs/${lData.id}/items`);
        if (res.ok) {
          const d = await res.json();
          setNewItems(d.items ?? []);
        }
      } else {
        setNewItems([]);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load briefing data");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  async function loadMore() {
    setLoadingMore(true);
    try {
      const offset = runs.length;
      const res = await fetch(`/api/runs?limit=${PAGE_SIZE}&offset=${offset}`);
      if (!res.ok) throw new Error("Failed to load more runs");
      const d = await res.json();
      setRuns((prev) => [...prev, ...(d.runs ?? [])]);
      setTotal(d.total ?? total);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load more runs");
    } finally {
      setLoadingMore(false);
    }
  }

  const pollRun = async (runId: string) => {
    const start = Date.now();
    while (Date.now() - start < POLL_TIMEOUT) {
      await new Promise((r) => setTimeout(r, POLL_INTERVAL));
      const res = await fetch(`/api/runs/${runId}`);
      if (res.ok) {
        const d = await res.json();
        if (d.status === "completed") {
          return d.run as Run;
        }
      } else if (res.status === 404) {
        // pending, continue
      } else {
        throw new Error("Fetch error while polling run");
      }
    }
    throw new Error("Timed out waiting for run");
  };

  async function runNow() {
    if (running) return;
    if (Date.now() - lastRunAt < RATE_MS) return;
    setRunning(true);
    setLastRunAt(Date.now());
    setError(null);
    setStatusMsg(null);
    try {
      const res = await fetch("/api/runs", { method: "POST" });
      if (res.status === 409) throw new Error("A run is already in progress (409)");
      if (res.status === 429) throw new Error("Rate limited (429)");
      if (!res.ok) throw new Error("Run failed");
      const data = await res.json();
      const run = await pollRun(data.runId);
      if (run.success) {
        setStatusMsg("Run succeeded");
      } else {
        setStatusMsg(`Run failed: ${run.error ?? "unknown error"}`);
      }
      await refresh();
    } catch (e) {
      const msg = e instanceof Error ? e.message : "Run failed";
      setError(msg);
    } finally {
      setRunning(false);
    }
  }

  const disabled = running || Date.now() - lastRunAt < RATE_MS;

  return (
    <main className="mx-auto max-w-5xl px-4 py-8 sm:px-6 lg:px-8">
      <header className="mb-6">
        <h1 className="text-2xl font-bold tracking-tight text-slate-900 sm:text-3xl">Confer Briefing</h1>
      </header>

      {error && (
        <div role="alert" aria-live="assertive" className="mb-4 rounded-md border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-700">
          {error}
        </div>
      )}

      {statusMsg && (
        <div role="status" aria-live="polite" className="mb-4 rounded-md border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-700">
          {statusMsg}
        </div>
      )}

      {loading && (
        <div role="status" aria-live="polite" className="mb-4 rounded-md border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-600">
          Loading latest briefing...
        </div>
      )}

      <section className="mb-6 rounded-lg border border-slate-200 bg-white p-4 shadow-sm">
        <h2 className="mb-3 text-xl font-semibold text-slate-900">Latest Briefing</h2>
        {latest ? (
          <>
            <p className="mb-3 text-sm text-slate-600">{new Date(latest.timestamp).toLocaleDateString()} · {latest.isBaseline ? "Baseline run - all items new" : `${latest.newItemCount} new since last run`}</p>
            {latest.success === false && (
              <p className="mb-2 text-sm text-red-600" role="alert">Latest run failed: {latest.error}</p>
            )}
            <ul className="space-y-2">
              {newItems.map((it) => (
                <li key={it.id}>
                  <a href={it.link} target="_blank" rel="noreferrer" className="text-blue-600 underline-offset-2 hover:underline focus:outline-none focus:ring-2 focus:ring-blue-500 rounded">
                    {it.title}
                  </a>
                </li>
              ))}
            </ul>
          </>
        ) : <p className="text-sm text-slate-600">No runs yet.</p>}
      </section>

      <button onClick={runNow} disabled={disabled} className="my-3 inline-flex items-center rounded-md bg-blue-600 px-4 py-2 text-white hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50">
        {running ? "Running..." : "Run Now"}
      </button>

      <section className="mt-6 rounded-lg border border-slate-200 bg-white p-4 shadow-sm">
        <h2 className="mb-3 text-xl font-semibold text-slate-900">Run History</h2>
        <div className="overflow-x-auto">
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-left">
                <th className="px-3 py-2 font-medium text-slate-700">Time</th>
                <th className="px-3 py-2 font-medium text-slate-700">Status</th>
                <th className="px-3 py-2 font-medium text-slate-700">New Items</th>
                <th className="px-3 py-2 font-medium text-slate-700">Error</th>
              </tr>
            </thead>
            <tbody>
              {runs.length === 0 && (
                <tr><td colSpan={4} className="px-3 py-4 text-center text-slate-500">No runs yet.</td></tr>
              )}
              {runs.map((r) => (
                <tr key={r.id} className="border-b border-slate-100">
                  <td className="px-3 py-2 text-slate-700">{new Date(r.timestamp).toLocaleString()}</td>
                  <td className="px-3 py-2">{r.success ? "✓" : "✗"}</td>
                  <td className="px-3 py-2 text-slate-700">{r.newItemCount}{r.isBaseline ? " (baseline)" : ""}</td>
                  <td className="px-3 py-2 text-red-600">{r.error ?? ""}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {runs.length < total && (
          <button onClick={loadMore} disabled={loadingMore} className="mt-3 inline-flex items-center rounded-md border border-slate-300 px-3 py-1.5 text-sm text-slate-700 hover:bg-slate-50">
            {loadingMore ? "Loading..." : "Load more"}
          </button>
        )}
      </section>
    </main>
  );
}
