import "./main.css";

import React, { startTransition, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

export async function init(ctx, data) {
  await ctx.importCSS("main.css");
  const root = createRoot(ctx.root);
  root.render(<SlavePanel ctx={ctx} initialData={data} />);
}

const STATUS_STYLES = {
  live: "bg-emerald-100 text-emerald-800",
  stale: "bg-amber-100 text-amber-800",
  unavailable: "bg-stone-200 text-stone-600",
};

const STATE_STYLES = {
  op: "bg-emerald-100 text-emerald-800",
  safeop: "bg-amber-100 text-amber-800",
  preop: "bg-orange-100 text-orange-800",
  init: "bg-stone-200 text-stone-600",
  unknown: "bg-stone-200 text-stone-500",
  unavailable: "bg-stone-200 text-stone-500",
};

const DOMAIN_STATE_STYLES = {
  cycling: "bg-emerald-100 text-emerald-800",
  open: "bg-sky-100 text-sky-800",
  stopped: "bg-rose-100 text-rose-800",
  unknown: "bg-stone-200 text-stone-500",
};

function badgeClass(value, styles) {
  return styles[value] ?? "bg-stone-200 text-stone-500";
}

function toHex(value, pad = 4) {
  if (value == null) return "n/a";
  return "0x" + (value >>> 0).toString(16).toUpperCase().padStart(pad, "0");
}

function Badge({ label, tone }) {
  return (
    <span className={`inline-flex items-center rounded-full px-2 py-0.5 font-mono text-[11px] font-medium ${tone}`}>
      {label}
    </span>
  );
}

function PanelHeader({ data, onRefresh }) {
  const { summary, status, runtime_error: runtimeError } = data;

  return (
    <div className="flex flex-wrap items-start justify-between gap-3 border-b border-stone-200 px-4 py-3">
      <div className="space-y-2">
        <div className="flex flex-wrap items-center gap-2">
          <h3 className="text-sm font-semibold tracking-tight text-stone-800">{summary.name}</h3>
          <Badge label={status} tone={badgeClass(status, STATUS_STYLES)} />
          <Badge label={summary.al_state} tone={badgeClass(summary.al_state, STATE_STYLES)} />
          {summary.coe === true && <Badge label="CoE" tone="bg-sky-100 text-sky-800" />}
        </div>

        <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-stone-500">
          {summary.station != null && <span className="font-mono">station {toHex(summary.station)}</span>}
          {summary.driver && <span className="font-mono">{summary.driver}</span>}
          {summary.configuration_error && (
            <span className="font-mono text-rose-700">config {summary.configuration_error}</span>
          )}
          {runtimeError && <span className="font-mono text-amber-700">runtime {runtimeError}</span>}
        </div>
      </div>

      <button
        onClick={onRefresh}
        className="rounded-full border border-stone-300 px-3 py-1 text-xs font-medium text-stone-600 transition hover:border-stone-400 hover:bg-white"
      >
        Refresh
      </button>
    </div>
  );
}

function DomainStrip({ domains }) {
  if (!domains.length) return null;

  return (
    <div className="flex flex-wrap gap-2 px-4 pt-3">
      {domains.map((domain) => (
        <div key={domain.id} className="rounded-xl border border-stone-200 bg-white/80 px-3 py-2">
          <div className="flex items-center gap-2">
            <span className="font-mono text-xs text-stone-700">{domain.id}</span>
            <Badge label={domain.state} tone={badgeClass(domain.state, DOMAIN_STATE_STYLES)} />
          </div>
          <div className="mt-1 flex gap-3 font-mono text-[11px] text-stone-500">
            <span className={domain.miss_count > 0 ? "text-rose-700" : ""}>miss {domain.miss_count}</span>
            <span className={domain.total_miss_count > 0 ? "text-rose-700" : ""}>
              total {domain.total_miss_count}
            </span>
            <span>wkc {domain.expected_wkc}</span>
          </div>
        </div>
      ))}
    </div>
  );
}

function IdentityCard({ identity }) {
  if (!identity) return null;

  return (
    <div className="px-4 pt-3">
      <div className="rounded-2xl border border-stone-200 bg-white/80 p-3">
        <div className="mb-2 text-[11px] font-semibold uppercase tracking-[0.18em] text-stone-400">
          Identity
        </div>
        <div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-4">
          <IdentityField label="Vendor" value={toHex(identity.vendor_id, 8)} />
          <IdentityField label="Product" value={toHex(identity.product_code, 8)} />
          <IdentityField label="Revision" value={toHex(identity.revision, 8)} />
          <IdentityField label="Serial" value={toHex(identity.serial_number, 8)} />
        </div>
      </div>
    </div>
  );
}

function IdentityField({ label, value }) {
  return (
    <div className="rounded-xl bg-stone-50 px-3 py-2">
      <div className="text-[11px] uppercase tracking-[0.18em] text-stone-400">{label}</div>
      <div className="mt-1 font-mono text-xs text-stone-700">{value}</div>
    </div>
  );
}

function SignalSection({ title, signals, ctx }) {
  return (
    <section className="rounded-2xl border border-stone-200 bg-white/80 p-3">
      <div className="mb-3 flex items-center justify-between">
        <h4 className="text-[11px] font-semibold uppercase tracking-[0.18em] text-stone-400">{title}</h4>
        <span className="font-mono text-[11px] text-stone-400">{signals.length}</span>
      </div>

      {signals.length === 0 ? (
        <div className="rounded-xl bg-stone-50 px-3 py-4 text-center font-mono text-xs text-stone-400">
          No signals
        </div>
      ) : (
        <div className="grid gap-2 md:grid-cols-2 2xl:grid-cols-3">
          {signals.map((signal) => (
            <SignalCard key={`${signal.direction}:${signal.name}`} signal={signal} ctx={ctx} />
          ))}
        </div>
      )}
    </section>
  );
}

function SignalCard({ signal, ctx }) {
  return (
    <article className="rounded-xl border border-stone-200 bg-stone-50/80 p-3">
      <div className="flex items-start justify-between gap-2">
        <div>
          <div className="font-mono text-xs font-semibold text-stone-700">{signal.name}</div>
          <div className="mt-1 font-mono text-[11px] text-stone-400">
            {signal.domain} • {signal.bit_size} bit
          </div>
        </div>
        {signal.kind === "bit" && (
          <span
            className={`mt-0.5 inline-block h-3 w-3 rounded-full ${
              signal.known ? (signal.active ? "bg-emerald-500 shadow-[0_0_12px_rgba(16,185,129,0.5)]" : "bg-stone-300") : "bg-amber-300"
            }`}
          />
        )}
      </div>

      <div className="mt-3 rounded-lg bg-white px-3 py-2 font-mono text-xs text-stone-700">
        {signal.display}
      </div>

      {signal.writable ? (
        <div className="mt-3 flex gap-2">
          <WriteButton
            active={signal.known && signal.active === false}
            label="Off"
            onClick={() => ctx.pushEvent("set_output", { signal: signal.name, value: 0 })}
          />
          <WriteButton
            active={signal.known && signal.active === true}
            label="On"
            onClick={() => ctx.pushEvent("set_output", { signal: signal.name, value: 1 })}
          />
        </div>
      ) : signal.direction === "output" ? (
        <div className="mt-3 text-[11px] text-stone-400">Write this signal manually in the notebook.</div>
      ) : null}
    </article>
  );
}

function WriteButton({ active, label, onClick }) {
  return (
    <button
      onClick={onClick}
      className={`flex-1 rounded-full border px-3 py-1.5 text-xs font-medium transition ${
        active
          ? "border-stone-800 bg-stone-800 text-white"
          : "border-stone-300 bg-white text-stone-600 hover:border-stone-400 hover:bg-stone-100"
      }`}
    >
      {label}
    </button>
  );
}

function AlertStrip({ writeError }) {
  if (!writeError) return null;

  return (
    <div className="px-4 pt-3">
      <div className="rounded-2xl border border-rose-200 bg-rose-50 px-3 py-2 font-mono text-xs text-rose-700">
        write {writeError.signal}: {writeError.reason}
      </div>
    </div>
  );
}

function EmptyState({ onRefresh }) {
  return (
    <div className="px-4 py-10 text-center">
      <div className="mx-auto max-w-sm space-y-3">
        <div className="text-sm font-semibold text-stone-700">Slave unavailable</div>
        <div className="font-mono text-xs text-stone-400">
          Start the master or refresh after the bus has been discovered.
        </div>
        <button
          onClick={onRefresh}
          className="rounded-full border border-stone-300 px-3 py-1.5 text-xs font-medium text-stone-600 transition hover:border-stone-400 hover:bg-white"
        >
          Refresh
        </button>
      </div>
    </div>
  );
}

function SlavePanel({ ctx, initialData }) {
  const [data, setData] = useState(initialData);

  useEffect(() => {
    ctx.handleEvent("snapshot", (nextData) => {
      startTransition(() => setData(nextData));
    });
  }, [ctx]);

  if (!data) return null;

  return (
    <div className="kino-ethercat-panel overflow-hidden">
      <PanelHeader data={data} onRefresh={() => ctx.pushEvent("refresh")} />
      {data.status === "unavailable" ? (
        <EmptyState onRefresh={() => ctx.pushEvent("refresh")} />
      ) : (
        <>
          <AlertStrip writeError={data.write_error} />
          <DomainStrip domains={data.domains} />
          <IdentityCard identity={data.summary.identity} />
          <div className="grid gap-3 px-4 py-4 xl:grid-cols-2">
            <SignalSection title="Inputs" signals={data.inputs} ctx={ctx} />
            <SignalSection title="Outputs" signals={data.outputs} ctx={ctx} />
          </div>
        </>
      )}
    </div>
  );
}
