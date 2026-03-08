import "./main.css";

import React, { startTransition, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

export async function init(ctx, data) {
  await ctx.importCSS("main.css");
  const root = createRoot(ctx.root);
  root.render(<SDOExplorer ctx={ctx} data={data} />);
}

const STATUS_STYLES = {
  ok: "bg-emerald-100 text-emerald-800",
  error: "bg-rose-100 text-rose-800",
};

function Badge({ label, tone }) {
  return (
    <span className={`inline-flex items-center rounded-full px-2 py-0.5 font-mono text-[11px] font-medium ${tone}`}>
      {label}
    </span>
  );
}

function formatTime(atMs) {
  if (!atMs) return "n/a";
  return new Date(atMs).toLocaleTimeString();
}

function ResultCard({ result }) {
  if (!result) {
    return (
      <div className="rounded-2xl border border-stone-200 bg-stone-50 px-4 py-6 text-center font-mono text-xs text-stone-400">
        Run an upload or download to inspect mailbox traffic.
      </div>
    );
  }

  return (
    <div className="rounded-2xl border border-stone-200 bg-white/80 p-4">
      <div className="flex flex-wrap items-center gap-2">
        <Badge label={result.status} tone={STATUS_STYLES[result.status] ?? STATUS_STYLES.ok} />
        <span className="font-mono text-xs text-stone-500">
          {result.operation} {result.slave} {result.index}:{result.subindex}
        </span>
      </div>
      <div className="mt-3 font-mono text-xs text-stone-700">{result.message}</div>
      {result.hex && (
        <div className="mt-3 grid gap-3 xl:grid-cols-2">
          <div className="rounded-xl bg-stone-50 p-3">
            <div className="mb-2 text-[11px] uppercase tracking-[0.18em] text-stone-400">Hex</div>
            <div className="break-all font-mono text-xs text-stone-700">{result.hex}</div>
          </div>
          <div className="rounded-xl bg-stone-50 p-3">
            <div className="mb-2 text-[11px] uppercase tracking-[0.18em] text-stone-400">ASCII</div>
            <div className="break-all font-mono text-xs text-stone-700">{result.ascii}</div>
          </div>
        </div>
      )}
      <div className="mt-3 font-mono text-[11px] text-stone-500">
        {result.bytes != null ? `${result.bytes} byte(s) • ` : ""}
        {formatTime(result.at_ms)}
      </div>
    </div>
  );
}

function HistoryList({ history }) {
  if (!history.length) return null;

  return (
    <div className="space-y-2">
      {history.map((entry, index) => (
        <div key={`${entry.at_ms}-${index}`} className="rounded-xl border border-stone-200 bg-stone-50 px-3 py-2">
          <div className="flex flex-wrap items-center gap-2">
            <Badge label={entry.status} tone={STATUS_STYLES[entry.status] ?? STATUS_STYLES.ok} />
            <span className="font-mono text-xs text-stone-700">
              {entry.operation} {entry.slave} {entry.index}:{entry.subindex}
            </span>
          </div>
          <div className="mt-1 font-mono text-[11px] text-stone-500">{entry.message}</div>
          {entry.hex && <div className="mt-1 break-all font-mono text-[11px] text-stone-500">{entry.hex}</div>}
        </div>
      ))}
    </div>
  );
}

function SDOExplorer({ ctx, data }) {
  const [snapshot, setSnapshot] = useState(data);
  const [slave, setSlave] = useState(data.selected_slave ?? "");
  const [index, setIndex] = useState(data.default_index ?? "0x1018");
  const [subindex, setSubindex] = useState(data.default_subindex ?? "0x00");
  const [writeData, setWriteData] = useState(data.default_write_data ?? "");

  useEffect(() => {
    ctx.handleEvent("snapshot", (next) => {
      startTransition(() => {
        setSnapshot(next);
        setSlave(next.selected_slave ?? "");
      });
    });
  }, [ctx]);

  const run = (operation) => {
    ctx.pushEvent("run", {
      operation,
      slave,
      index,
      subindex,
      write_data: writeData,
    });
  };

  return (
    <div className="kino-ethercat-sdo space-y-4 p-4 font-sans text-sm">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h3 className="text-sm font-semibold tracking-tight text-stone-800">Mailbox / SDO explorer</h3>
          <div className="mt-1 font-mono text-xs text-stone-500">
            Discover CoE slaves, inspect object entries, and push raw mailbox payloads as hex bytes.
          </div>
        </div>
        <button
          onClick={() => ctx.pushEvent("refresh_slaves")}
          className="rounded-full border border-stone-300 px-3 py-1 text-xs font-medium text-stone-600 transition hover:border-stone-400 hover:bg-white"
        >
          Refresh slaves
        </button>
      </div>

      <div className="grid gap-3 xl:grid-cols-3">
        <label className="space-y-1">
          <span className="text-[11px] font-semibold uppercase tracking-[0.18em] text-stone-400">Slave</span>
          <select
            className="w-full rounded-xl border border-stone-300 bg-white px-3 py-2 font-mono text-xs text-stone-700 focus:outline-none focus:border-stone-500"
            value={slave}
            onChange={(event) => setSlave(event.target.value)}
          >
            <option value="">Select CoE slave</option>
            {snapshot.slaves.map((entry) => (
              <option key={entry.name} value={entry.name}>
                {entry.label}
              </option>
            ))}
          </select>
        </label>

        <label className="space-y-1">
          <span className="text-[11px] font-semibold uppercase tracking-[0.18em] text-stone-400">Index</span>
          <input
            className="w-full rounded-xl border border-stone-300 bg-white px-3 py-2 font-mono text-xs text-stone-700 focus:outline-none focus:border-stone-500"
            value={index}
            onChange={(event) => setIndex(event.target.value)}
            placeholder="0x1018"
          />
        </label>

        <label className="space-y-1">
          <span className="text-[11px] font-semibold uppercase tracking-[0.18em] text-stone-400">Subindex</span>
          <input
            className="w-full rounded-xl border border-stone-300 bg-white px-3 py-2 font-mono text-xs text-stone-700 focus:outline-none focus:border-stone-500"
            value={subindex}
            onChange={(event) => setSubindex(event.target.value)}
            placeholder="0x00"
          />
        </label>
      </div>

      <label className="space-y-1 block">
        <span className="text-[11px] font-semibold uppercase tracking-[0.18em] text-stone-400">Download payload</span>
        <textarea
          className="min-h-28 w-full rounded-2xl border border-stone-300 bg-white px-3 py-2 font-mono text-xs text-stone-700 focus:outline-none focus:border-stone-500"
          value={writeData}
          onChange={(event) => setWriteData(event.target.value)}
          placeholder="04 or DE AD BE EF"
        />
      </label>

      <div className="flex flex-wrap gap-2">
        <button
          onClick={() => run("upload")}
          className="rounded-full border border-stone-800 bg-stone-800 px-4 py-1.5 text-xs font-medium text-white transition hover:bg-stone-700"
        >
          Upload
        </button>
        <button
          onClick={() => run("download")}
          className="rounded-full border border-amber-500 bg-amber-500 px-4 py-1.5 text-xs font-medium text-stone-950 transition hover:bg-amber-400"
        >
          Download
        </button>
      </div>

      <ResultCard result={snapshot.result} />

      <div>
        <div className="mb-2 text-[11px] font-semibold uppercase tracking-[0.18em] text-stone-400">Recent operations</div>
        <HistoryList history={snapshot.history} />
      </div>
    </div>
  );
}
