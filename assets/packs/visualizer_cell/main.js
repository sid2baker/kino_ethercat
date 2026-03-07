import "./main.css";

import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

export async function init(ctx, data) {
  await ctx.importCSS("main.css");
  const root = createRoot(ctx.root);
  root.render(<VisualizerCell ctx={ctx} data={data} />);
}

const LAYOUT_OPTIONS = [
  { value: "columns", label: "Side by side" },
  { value: "list", label: "Top to bottom" },
];

// ── Slave row ─────────────────────────────────────────────────────────────────

function SlaveRow({ name, checked, opts, stale, onToggle, onOptsChange }) {
  return (
    <li className="flex flex-col gap-1 py-1.5 border-t border-gray-100 first:border-t-0">
      <div className="flex items-center gap-2">
        <input
          type="checkbox"
          id={`slave-${name}`}
          checked={checked}
          onChange={(e) => onToggle(name, e.target.checked)}
          className="rounded border-gray-300 text-blue-500 focus:ring-blue-400"
        />
        <label
          htmlFor={`slave-${name}`}
          className={`font-mono text-sm cursor-pointer ${stale ? "text-gray-400 line-through" : "text-gray-700"}`}
        >
          {name}
          {stale && <span className="ml-2 text-xs font-sans normal-case no-underline text-gray-400">(not running)</span>}
        </label>
        {checked && (
          <select
            className="ml-auto border border-gray-300 rounded px-1.5 py-0.5 text-xs focus:outline-none focus:border-blue-400 bg-white text-gray-500"
            value={opts.layout}
            onChange={(e) => onOptsChange(name, { layout: e.target.value })}
          >
            {LAYOUT_OPTIONS.map((o) => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </select>
        )}
      </div>
    </li>
  );
}

// ── Main component ────────────────────────────────────────────────────────────

function VisualizerCell({ ctx, data }) {
  const [available, setAvailable] = useState(data.available ?? []);
  const [selected, setSelected] = useState(data.selected ?? []);
  const [status, setStatus] = useState(data.status ?? "ok");

  useEffect(() => {
    ctx.handleEvent("refreshed", ({ available, status }) => {
      setAvailable(available);
      setStatus(status);
    });
  }, []);

  const handleRefresh = () => ctx.pushEvent("refresh");

  const selectedNames = new Set(selected.map((s) => s.name));

  // All names to show: available + stale selected entries no longer in available
  const staleNames = selected.map((s) => s.name).filter((n) => !available.includes(n));
  const allNames = [...available, ...staleNames];

  const handleToggle = (name, checked) => {
    if (checked) {
      const entry = { name, layout: "columns", on_error: "placeholder" };
      const next = [...selected, entry];
      setSelected(next);
      ctx.pushEvent("select", { name });
    } else {
      const next = selected.filter((s) => s.name !== name);
      setSelected(next);
      ctx.pushEvent("deselect", { name });
    }
  };

  const handleOptsChange = (name, opts) => {
    const next = selected.map((s) => (s.name === name ? { ...s, ...opts } : s));
    setSelected(next);
    ctx.pushEvent("update_opts", { name, layout: opts.layout });
  };

  const getOpts = (name) =>
    selected.find((s) => s.name === name) ?? { layout: "columns" };

  return (
    <div className="p-3 space-y-3 font-sans text-sm select-none">
      {/* Header row */}
      <div className="flex items-center gap-2">
        <span className="text-gray-600 font-medium">EtherCAT slaves</span>
        <button
          onClick={handleRefresh}
          className="px-2 py-0.5 text-xs border border-gray-300 rounded text-gray-500 hover:bg-gray-50 hover:border-gray-400 transition-colors"
        >
          Refresh
        </button>
        {status === "not_running" && (
          <span className="text-xs text-amber-600 font-mono">EtherCAT not running</span>
        )}
      </div>

      {/* Slave list */}
      {allNames.length === 0 ? (
        <p className="text-xs text-gray-400 font-mono">
          No slaves found — start EtherCAT first, then click Refresh.
        </p>
      ) : (
        <ul className="space-y-0">
          {allNames.map((name) => (
            <SlaveRow
              key={name}
              name={name}
              checked={selectedNames.has(name)}
              opts={getOpts(name)}
              stale={staleNames.includes(name)}
              onToggle={handleToggle}
              onOptsChange={handleOptsChange}
            />
          ))}
        </ul>
      )}

      {/* Hint */}
      {allNames.length > 0 && selectedNames.size === 0 && (
        <p className="text-xs text-gray-400">Select at least one slave to generate code.</p>
      )}
    </div>
  );
}
