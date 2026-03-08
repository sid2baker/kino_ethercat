import "./main.css";

import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

export async function init(ctx, data) {
  await ctx.importCSS("main.css");
  const root = createRoot(ctx.root);
  root.render(<Diagnostics ctx={ctx} data={data} />);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function toHex(n, pad = 4) {
  return "0x" + (n >>> 0).toString(16).toUpperCase().padStart(pad, "0");
}

function Badge({ label, className }) {
  return (
    <span className={`inline-block px-1.5 py-0.5 rounded text-xs font-mono font-medium ${className}`}>
      {label}
    </span>
  );
}

// ── Phase badge ───────────────────────────────────────────────────────────────

const PHASE_STYLES = {
  idle: "bg-gray-100 text-gray-500",
  scanning: "bg-blue-100 text-blue-700 animate-pulse",
  configuring: "bg-yellow-100 text-yellow-700 animate-pulse",
  preop_ready: "bg-yellow-100 text-yellow-700",
  operational: "bg-green-100 text-green-700",
  degraded: "bg-red-100 text-red-700",
};

function PhaseBadge({ phase }) {
  return <Badge label={phase} className={PHASE_STYLES[phase] ?? "bg-gray-100 text-gray-400"} />;
}

// ── ESM state badge ───────────────────────────────────────────────────────────

const ESM_STYLES = {
  op: "bg-green-100 text-green-700",
  safeop: "bg-yellow-100 text-yellow-700",
  preop: "bg-amber-100 text-amber-700",
  init: "bg-gray-100 text-gray-500",
  bootstrap: "bg-purple-100 text-purple-700",
  unknown: "bg-red-100 text-red-600",
};

function EsmBadge({ state }) {
  return <Badge label={state} className={ESM_STYLES[state] ?? ESM_STYLES.unknown} />;
}

// ── Domain state badge ────────────────────────────────────────────────────────

const DOMAIN_STYLES = {
  cycling: "bg-green-100 text-green-700",
  open: "bg-gray-100 text-gray-500",
  stopped: "bg-red-100 text-red-600",
  unknown: "bg-gray-100 text-gray-400",
};

function DomainStateBadge({ state }) {
  return <Badge label={state} className={DOMAIN_STYLES[state] ?? DOMAIN_STYLES.unknown} />;
}

// ── DC lock badge ─────────────────────────────────────────────────────────────

const DC_LOCK_STYLES = {
  locked: "bg-green-100 text-green-700",
  locking: "bg-yellow-100 text-yellow-700 animate-pulse",
  unavailable: "bg-gray-100 text-gray-500",
  inactive: "bg-gray-100 text-gray-400",
  disabled: "bg-gray-100 text-gray-300",
};

function DcLockBadge({ state }) {
  return <Badge label={state} className={DC_LOCK_STYLES[state] ?? "bg-gray-100 text-gray-400"} />;
}

// ── Section header ────────────────────────────────────────────────────────────

function Section({ title, children }) {
  return (
    <div>
      <div className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1.5">
        {title}
      </div>
      {children}
    </div>
  );
}

// ── Table helpers ─────────────────────────────────────────────────────────────

function Th({ children, right }) {
  return (
    <th className={`pb-1 text-xs font-medium text-gray-400 ${right ? "text-right" : "text-left"}`}>
      {children}
    </th>
  );
}

function Td({ children, mono, right, muted, danger }) {
  return (
    <td
      className={[
        "py-1 pr-4 text-xs",
        mono ? "font-mono" : "",
        right ? "text-right" : "",
        danger ? "text-red-600 font-mono" : muted ? "text-gray-400" : "text-gray-700",
      ]
        .filter(Boolean)
        .join(" ")}
    >
      {children}
    </td>
  );
}

// ── Slaves table ──────────────────────────────────────────────────────────────

function SlavesTable({ slaves }) {
  if (slaves.length === 0) {
    return <p className="text-xs text-gray-400 font-mono">No slaves running.</p>;
  }

  return (
    <table className="w-full border-collapse">
      <thead>
        <tr>
          <Th>Name</Th>
          <Th>Station</Th>
          <Th>State</Th>
          <Th>AL Error</Th>
          <Th>Config Error</Th>
        </tr>
      </thead>
      <tbody className="divide-y divide-gray-100">
        {slaves.map((s) => (
          <tr key={s.name}>
            <Td mono>{s.name}</Td>
            <Td mono muted>{toHex(s.station)}</Td>
            <td className="py-1 pr-4">
              <EsmBadge state={s.al_state} />
            </td>
            <Td mono muted={s.al_error == null}>
              {s.al_error != null ? toHex(s.al_error, 4) : "—"}
            </Td>
            <Td danger={s.configuration_error != null} muted={s.configuration_error == null}>
              {s.configuration_error ?? "—"}
            </Td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

// ── Domains table ─────────────────────────────────────────────────────────────

function DomainsTable({ domains }) {
  if (domains.length === 0) {
    return <p className="text-xs text-gray-400 font-mono">No domains running.</p>;
  }

  return (
    <table className="w-full border-collapse">
      <thead>
        <tr>
          <Th>Domain</Th>
          <Th>State</Th>
          <Th right>Cycle</Th>
          <Th right>Cycles</Th>
          <Th right>Misses</Th>
          <Th right>Total</Th>
          <Th right>WKC</Th>
        </tr>
      </thead>
      <tbody className="divide-y divide-gray-100">
        {domains.map((d) => (
          <tr key={d.id}>
            <Td mono>{d.id}</Td>
            <td className="py-1 pr-4">
              <DomainStateBadge state={d.state} />
            </td>
            <Td mono right muted>{d.cycle_time_us.toLocaleString()} µs</Td>
            <Td mono right>{d.cycle_count.toLocaleString()}</Td>
            <Td mono right danger={d.miss_count > 0}>{d.miss_count}</Td>
            <Td mono right muted={d.total_miss_count === 0} danger={d.total_miss_count > 0}>
              {d.total_miss_count}
            </Td>
            <Td mono right muted>{d.expected_wkc}</Td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

// ── DC section ────────────────────────────────────────────────────────────────

function DcSection({ dc }) {
  if (!dc || !dc.configured) return null;

  const diffColor =
    dc.max_sync_diff_ns == null
      ? "text-gray-400"
      : dc.max_sync_diff_ns > 5000
      ? "text-red-600"
      : dc.max_sync_diff_ns > 1000
      ? "text-yellow-600"
      : "text-green-600";

  return (
    <Section title="Distributed Clocks">
      <div className="flex flex-wrap items-center gap-x-5 gap-y-1 text-xs">
        <span className="flex items-center gap-1.5">
          <span className="text-gray-400">Lock</span>
          <DcLockBadge state={dc.lock_state} />
        </span>
        {dc.reference_clock && (
          <span className="flex items-center gap-1.5">
            <span className="text-gray-400">Ref</span>
            <span className="font-mono text-gray-700">{dc.reference_clock}</span>
          </span>
        )}
        {dc.cycle_ns != null && (
          <span className="flex items-center gap-1.5">
            <span className="text-gray-400">Cycle</span>
            <span className="font-mono text-gray-700">{dc.cycle_ns.toLocaleString()} ns</span>
          </span>
        )}
        {dc.max_sync_diff_ns != null && (
          <span className="flex items-center gap-1.5">
            <span className="text-gray-400">Δmax</span>
            <span className={`font-mono ${diffColor}`}>{dc.max_sync_diff_ns.toLocaleString()} ns</span>
          </span>
        )}
        <span className="flex items-center gap-1.5">
          <span className="text-gray-400">Failures</span>
          <span className={`font-mono ${dc.monitor_failures > 0 ? "text-red-600" : "text-gray-500"}`}>
            {dc.monitor_failures}
          </span>
        </span>
      </div>
    </Section>
  );
}

// ── Main component ────────────────────────────────────────────────────────────

function Diagnostics({ ctx, data }) {
  const [snap, setSnap] = useState(data);

  useEffect(() => {
    ctx.handleEvent("snapshot", setSnap);
  }, []);

  return (
    <div className="p-3 space-y-4 font-sans text-sm select-none">
      {/* Header */}
      <div className="flex items-center justify-between">
        <span className="font-medium text-gray-600">EtherCAT Diagnostics</span>
        <PhaseBadge phase={snap.phase} />
      </div>

      {/* Last failure banner */}
      {snap.last_failure && (
        <div className="px-2 py-1.5 bg-red-50 border border-red-200 rounded text-xs font-mono text-red-700 break-all">
          <span className="font-semibold mr-1">Last failure:</span>
          {snap.last_failure}
        </div>
      )}

      {/* Slaves */}
      <Section title="Slaves">
        <SlavesTable slaves={snap.slaves} />
      </Section>

      {/* Domains */}
      <Section title="Domains">
        <DomainsTable domains={snap.domains} />
      </Section>

      {/* DC */}
      <DcSection dc={snap.dc} />
    </div>
  );
}
