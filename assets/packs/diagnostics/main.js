import "./main.css";

import React, { startTransition, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

export async function init(ctx, data) {
  await ctx.importCSS("main.css");
  const root = createRoot(ctx.root);
  root.render(<Diagnostics ctx={ctx} data={data} />);
}

const PHASE_STYLES = {
  idle: "bg-stone-200 text-stone-600",
  scanning: "bg-sky-100 text-sky-800",
  configuring: "bg-amber-100 text-amber-800",
  preop_ready: "bg-amber-100 text-amber-800",
  operational: "bg-emerald-100 text-emerald-800",
  degraded: "bg-rose-100 text-rose-800",
};

const EVENT_STYLES = {
  info: "border-sky-200 bg-sky-50 text-sky-800",
  warn: "border-amber-200 bg-amber-50 text-amber-800",
  danger: "border-rose-200 bg-rose-50 text-rose-800",
};

const DOMAIN_STYLES = {
  cycling: "bg-emerald-100 text-emerald-800",
  open: "bg-sky-100 text-sky-800",
  stopped: "bg-rose-100 text-rose-800",
  unknown: "bg-stone-200 text-stone-500",
};

const LOCK_STYLES = {
  locked: "bg-emerald-100 text-emerald-800",
  locking: "bg-amber-100 text-amber-800",
  unavailable: "bg-stone-200 text-stone-600",
  inactive: "bg-stone-200 text-stone-500",
  disabled: "bg-stone-200 text-stone-400",
};

const SLAVE_STATE_STYLES = {
  op: "bg-emerald-100 text-emerald-800",
  safeop: "bg-amber-100 text-amber-800",
  preop: "bg-orange-100 text-orange-800",
  init: "bg-stone-200 text-stone-600",
  unknown: "bg-stone-200 text-stone-500",
};

function badgeClass(styles, key) {
  return styles[key] ?? "bg-stone-200 text-stone-500";
}

function Badge({ label, tone }) {
  return (
    <span className={`inline-flex items-center rounded-full px-2 py-0.5 font-mono text-[11px] font-medium ${tone}`}>
      {label}
    </span>
  );
}

function Sparkline({ values, tone = "#0f766e", max = null }) {
  if (!values?.length) {
    return <div className="h-12 rounded-xl bg-stone-100" />;
  }

  const chartValues = max ? values.map((value) => Math.min(value, max)) : values;
  const width = 120;
  const height = 42;
  const minValue = Math.min(...chartValues);
  const maxValue = Math.max(...chartValues);
  const range = Math.max(maxValue - minValue, 1);

  const points = chartValues
    .map((value, index) => {
      const x = (index / Math.max(chartValues.length - 1, 1)) * width;
      const y = height - ((value - minValue) / range) * (height - 4) - 2;
      return `${x},${y}`;
    })
    .join(" ");

  return (
    <svg viewBox={`0 0 ${width} ${height}`} className="h-12 w-full rounded-xl bg-stone-100/70">
      <polyline fill="none" stroke={tone} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" points={points} />
    </svg>
  );
}

function formatCount(value) {
  if (value == null) return "n/a";
  return value.toLocaleString();
}

function formatUs(value) {
  if (value == null) return "n/a";
  return `${value.toLocaleString()} us`;
}

function formatNs(value) {
  if (value == null) return "n/a";
  return `${value.toLocaleString()} ns`;
}

function formatHex(value, pad = 4) {
  if (value == null) return "n/a";
  return "0x" + (value >>> 0).toString(16).toUpperCase().padStart(pad, "0");
}

function formatTime(atMs) {
  if (!atMs) return "n/a";
  return new Date(atMs).toLocaleTimeString();
}

function SummaryHeader({ data }) {
  return (
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div className="space-y-2">
        <div className="flex flex-wrap items-center gap-2">
          <h3 className="text-lg font-semibold tracking-tight text-stone-800">Master diagnostics</h3>
          <Badge label={data.phase} tone={badgeClass(PHASE_STYLES, data.phase)} />
          <Badge label={data.dc?.lock_state ?? "disabled"} tone={badgeClass(LOCK_STYLES, data.dc?.lock_state ?? "disabled")} />
        </div>
        <div className="font-mono text-xs text-stone-500">
          {data.last_failure ? `last failure ${data.last_failure}` : "no recorded master failure"}
        </div>
      </div>
      <div className="grid gap-2 text-right text-xs text-stone-500">
        <div className="font-mono">expired realtime {formatCount(data.bus.expired_realtime)}</div>
        <div className="font-mono">bus exceptions {formatCount(data.bus.exceptions)}</div>
      </div>
    </div>
  );
}

function MetricCard({ title, accent, summary, children }) {
  return (
    <section className="rounded-2xl border border-stone-200 bg-white/80 p-3">
      <div className="mb-2 flex items-center justify-between gap-2">
        <div>
          <div className="text-[11px] font-semibold uppercase tracking-[0.18em] text-stone-400">{title}</div>
          <div className="mt-1 font-mono text-xs text-stone-600">{summary}</div>
        </div>
        <div className="h-3 w-3 rounded-full" style={{ backgroundColor: accent }} />
      </div>
      {children}
    </section>
  );
}

function TransactionSection({ transactions, queues }) {
  return (
    <div className="grid gap-3 xl:grid-cols-2">
      <MetricCard
        title="Realtime Bus"
        accent="#0f766e"
        summary={`last ${formatUs(transactions.realtime.last_latency_us)} • avg ${formatUs(transactions.realtime.avg_latency_us)}`}
      >
        <Sparkline values={transactions.realtime.latency_history} tone="#0f766e" />
        <div className="mt-3 grid grid-cols-2 gap-2 font-mono text-[11px] text-stone-500">
          <span>dispatches {formatCount(transactions.realtime.dispatches)}</span>
          <span>transactions {formatCount(transactions.realtime.transactions)}</span>
          <span>datagrams {formatCount(transactions.realtime.datagrams)}</span>
          <span>last wkc {formatCount(transactions.realtime.last_wkc)}</span>
          <span>queue peak {formatCount(queues.realtime.peak_depth)}</span>
          <span>queue last {formatCount(queues.realtime.last_depth)}</span>
        </div>
      </MetricCard>

      <MetricCard
        title="Reliable Bus"
        accent="#1d4ed8"
        summary={`last ${formatUs(transactions.reliable.last_latency_us)} • avg ${formatUs(transactions.reliable.avg_latency_us)}`}
      >
        <Sparkline values={transactions.reliable.latency_history} tone="#1d4ed8" />
        <div className="mt-3 grid grid-cols-2 gap-2 font-mono text-[11px] text-stone-500">
          <span>dispatches {formatCount(transactions.reliable.dispatches)}</span>
          <span>transactions {formatCount(transactions.reliable.transactions)}</span>
          <span>datagrams {formatCount(transactions.reliable.datagrams)}</span>
          <span>last wkc {formatCount(transactions.reliable.last_wkc)}</span>
          <span>queue peak {formatCount(queues.reliable.peak_depth)}</span>
          <span>queue last {formatCount(queues.reliable.last_depth)}</span>
        </div>
      </MetricCard>
    </div>
  );
}

function FrameSection({ frames, links }) {
  return (
    <div className="grid gap-3 xl:grid-cols-[1.4fr_1fr]">
      <MetricCard
        title="Frames"
        accent="#7c3aed"
        summary={`last RTT ${formatNs(frames.last_rtt_ns)} • peak ${formatNs(frames.peak_rtt_ns)}`}
      >
        <Sparkline values={frames.rtt_history} tone="#7c3aed" />
        <div className="mt-3 grid grid-cols-2 gap-2 font-mono text-[11px] text-stone-500">
          <span>sent {formatCount(frames.sent)}</span>
          <span>received {formatCount(frames.received)}</span>
          <span className={frames.dropped > 0 ? "text-rose-700" : ""}>dropped {formatCount(frames.dropped)}</span>
          <span>ignored {formatCount(frames.ignored)}</span>
        </div>
        {frames.dropped_reasons.length > 0 && (
          <div className="mt-3 flex flex-wrap gap-2">
            {frames.dropped_reasons.map((reason) => (
              <Badge key={reason.reason} label={`${reason.reason} ${reason.count}`} tone="bg-rose-100 text-rose-700" />
            ))}
          </div>
        )}
      </MetricCard>

      <section className="rounded-2xl border border-stone-200 bg-white/80 p-3">
        <div className="mb-3 text-[11px] font-semibold uppercase tracking-[0.18em] text-stone-400">Links</div>
        {links.length === 0 ? (
          <div className="rounded-xl bg-stone-50 px-3 py-4 text-center font-mono text-xs text-stone-400">No link telemetry yet</div>
        ) : (
          <div className="space-y-2">
            {links.map((link) => (
              <div key={link.name} className="rounded-xl border border-stone-200 bg-stone-50 px-3 py-2">
                <div className="flex items-center justify-between gap-2">
                  <span className="font-mono text-xs text-stone-700">{link.name}</span>
                  <Badge label={link.status} tone={link.status === "down" ? "bg-rose-100 text-rose-700" : "bg-emerald-100 text-emerald-700"} />
                </div>
                <div className="mt-1 font-mono text-[11px] text-stone-500">
                  {link.reason ? `${link.reason} • ` : ""}
                  {formatTime(link.at_ms)}
                </div>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

function DcSection({ dc }) {
  return (
    <section className="rounded-2xl border border-stone-200 bg-white/80 p-3">
      <div className="mb-3 flex flex-wrap items-center gap-2">
        <div className="text-[11px] font-semibold uppercase tracking-[0.18em] text-stone-400">Distributed Clocks</div>
        <Badge label={dc.lock_state} tone={badgeClass(LOCK_STYLES, dc.lock_state)} />
      </div>

      <div className="grid gap-3 xl:grid-cols-[1.2fr_1fr]">
        <div>
          <Sparkline values={dc.sync_diff_history} tone="#be123c" />
          <div className="mt-3 grid grid-cols-2 gap-2 font-mono text-[11px] text-stone-500">
            <span>tick wkc {formatCount(dc.tick_wkc)}</span>
            <span>failures {formatCount(dc.monitor_failures)}</span>
            <span>cycle {formatNs(dc.cycle_ns)}</span>
            <span>max diff {formatNs(dc.max_sync_diff_ns)}</span>
          </div>
        </div>
        <div className="space-y-2">
          {dc.lock_events?.length ? (
            dc.lock_events.slice().reverse().map((event, index) => (
              <div key={`${event.from}-${event.to}-${index}`} className="rounded-xl border border-stone-200 bg-stone-50 px-3 py-2">
                <div className="font-mono text-xs text-stone-700">{event.from} → {event.to}</div>
                <div className="mt-1 font-mono text-[11px] text-stone-500">{formatNs(event.max_sync_diff_ns)}</div>
              </div>
            ))
          ) : (
            <div className="rounded-xl bg-stone-50 px-3 py-4 text-center font-mono text-xs text-stone-400">No DC lock changes yet</div>
          )}
        </div>
      </div>
    </section>
  );
}

function DomainsSection({ domains }) {
  return (
    <section className="rounded-2xl border border-stone-200 bg-white/80 p-3">
      <div className="mb-3 text-[11px] font-semibold uppercase tracking-[0.18em] text-stone-400">Domains</div>
      {domains.length === 0 ? (
        <div className="rounded-xl bg-stone-50 px-3 py-4 text-center font-mono text-xs text-stone-400">No domains running</div>
      ) : (
        <div className="grid gap-3 xl:grid-cols-2">
          {domains.map((domain) => (
            <div key={domain.id} className="rounded-xl border border-stone-200 bg-stone-50/80 p-3">
              <div className="flex items-center justify-between gap-2">
                <span className="font-mono text-xs font-semibold text-stone-700">{domain.id}</span>
                <Badge label={domain.state} tone={badgeClass(DOMAIN_STYLES, domain.state)} />
              </div>
              <div className="mt-3">
                <Sparkline values={domain.cycle_history} tone="#d97706" />
              </div>
              <div className="mt-3 grid grid-cols-2 gap-2 font-mono text-[11px] text-stone-500">
                <span>last {formatUs(domain.last_cycle_us)}</span>
                <span>avg {formatUs(domain.avg_cycle_us)}</span>
                <span>misses {formatCount(domain.miss_count)}</span>
                <span>miss events {formatCount(domain.missed_events)}</span>
                <span>total misses {formatCount(domain.total_miss_count)}</span>
                <span>wkc {formatCount(domain.expected_wkc)}</span>
              </div>
              {(domain.last_miss_reason || domain.stop_reason || domain.crash_reason) && (
                <div className="mt-3 rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 font-mono text-[11px] text-amber-800">
                  {domain.crash_reason ? `crashed ${domain.crash_reason}` : domain.stop_reason ? `stopped ${domain.stop_reason}` : `missed ${domain.last_miss_reason}`}
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </section>
  );
}

function SlavesSection({ slaves }) {
  return (
    <section className="rounded-2xl border border-stone-200 bg-white/80 p-3">
      <div className="mb-3 text-[11px] font-semibold uppercase tracking-[0.18em] text-stone-400">Slaves</div>
      {slaves.length === 0 ? (
        <div className="rounded-xl bg-stone-50 px-3 py-4 text-center font-mono text-xs text-stone-400">No slaves running</div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full border-collapse">
            <thead>
              <tr className="text-left text-[11px] uppercase tracking-[0.18em] text-stone-400">
                <th className="pb-2">Name</th>
                <th className="pb-2">Station</th>
                <th className="pb-2">State</th>
                <th className="pb-2">AL</th>
                <th className="pb-2">Config</th>
                <th className="pb-2">Event</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-stone-100">
              {slaves.map((slave) => (
                <tr key={slave.name}>
                  <td className="py-2 pr-3 font-mono text-xs text-stone-700">{slave.name}</td>
                  <td className="py-2 pr-3 font-mono text-xs text-stone-500">{slave.station != null ? formatHex(slave.station) : "n/a"}</td>
                  <td className="py-2 pr-3">
                    <Badge label={slave.al_state} tone={badgeClass(SLAVE_STATE_STYLES, slave.al_state)} />
                  </td>
                  <td className="py-2 pr-3 font-mono text-xs text-stone-500">{slave.al_error != null ? formatHex(slave.al_error) : "n/a"}</td>
                  <td className="py-2 pr-3 text-xs text-stone-500">{slave.configuration_error ?? "n/a"}</td>
                  <td className="py-2 text-xs text-stone-500">
                    {slave.last_event ? `${slave.last_event.title} • ${formatTime(slave.last_event.at_ms)}` : "n/a"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

function TimelineSection({ timeline }) {
  return (
    <section className="rounded-2xl border border-stone-200 bg-white/80 p-3">
      <div className="mb-3 text-[11px] font-semibold uppercase tracking-[0.18em] text-stone-400">Timeline</div>
      {timeline.length === 0 ? (
        <div className="rounded-xl bg-stone-50 px-3 py-4 text-center font-mono text-xs text-stone-400">No fault or recovery events yet</div>
      ) : (
        <div className="space-y-2">
          {timeline.map((event) => (
            <div key={event.id} className={`rounded-xl border px-3 py-2 ${EVENT_STYLES[event.level] ?? EVENT_STYLES.info}`}>
              <div className="flex items-center justify-between gap-2">
                <div className="font-medium">{event.title}</div>
                <div className="font-mono text-[11px]">{formatTime(event.at_ms)}</div>
              </div>
              <div className="mt-1 font-mono text-[11px]">{event.detail}</div>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}

function Diagnostics({ ctx, data }) {
  const [snapshot, setSnapshot] = useState(data);

  useEffect(() => {
    ctx.handleEvent("snapshot", (next) => {
      startTransition(() => setSnapshot(next));
    });
  }, [ctx]);

  return (
    <div className="kino-ethercat-diagnostics space-y-3 p-4 font-sans text-sm">
      <SummaryHeader data={snapshot} />
      <TransactionSection transactions={snapshot.bus.transactions} queues={snapshot.bus.queues} />
      <FrameSection frames={snapshot.bus.frames} links={snapshot.bus.links} />
      <DcSection dc={snapshot.dc} />
      <DomainsSection domains={snapshot.domains} />
      <SlavesSection slaves={snapshot.slaves} />
      <TimelineSection timeline={snapshot.timeline} />
    </div>
  );
}
