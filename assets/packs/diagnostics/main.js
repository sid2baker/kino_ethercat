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

function sliceWindowLabel(sliceMs) {
  if (!sliceMs) return "rolling slices";
  if (sliceMs % 1000 === 0) return `${sliceMs / 1000}s slices`;
  return `${sliceMs} ms slices`;
}

function sliceTitle(slice, formatter) {
  const parts = [`${slice.label}`];

  if (slice.value != null) {
    parts.push(`value ${formatter(slice.value)}`);
  }

  if (slice.peak != null) {
    parts.push(`peak ${formatter(slice.peak)}`);
  }

  if (slice.count != null) {
    parts.push(`samples ${formatCount(slice.count)}`);
  }

  return parts.join(" • ");
}

function SliceBars({
  slices,
  color = "#0f766e",
  formatter = formatCount,
  emptyLabel = "No samples yet",
}) {
  if (!slices?.length) {
    return (
      <div className="flex h-28 items-center justify-center rounded-2xl bg-stone-100/80 font-mono text-[11px] text-stone-400">
        {emptyLabel}
      </div>
    );
  }

  const peak = Math.max(
    ...slices.map((slice) => {
      const candidate = slice.peak ?? slice.value ?? 0;
      return Number.isFinite(candidate) ? candidate : 0;
    }),
    1,
  );

  return (
    <div className="rounded-2xl border border-stone-200 bg-stone-50/80 px-3 py-3">
      <div className="flex h-28 items-end gap-1.5">
        {slices.map((slice) => {
          const value = slice.value ?? 0;
          const height = Math.max((value / peak) * 100, value > 0 ? 6 : 2);

          return (
            <div key={slice.at_ms} className="group flex min-w-0 flex-1 flex-col items-center justify-end gap-1">
              <div
                className="w-full rounded-t-xl rounded-b-md transition-transform duration-150 group-hover:-translate-y-1"
                style={{
                  height: `${height}%`,
                  background: `linear-gradient(180deg, ${color}, ${color}CC)`,
                }}
                title={sliceTitle(slice, formatter)}
              />
              <div className="truncate font-mono text-[10px] text-stone-400">{slice.label.slice(3)}</div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function SliceMetric({ title, subtitle, slices, color, formatter, emptyLabel }) {
  return (
    <div className="space-y-2 rounded-2xl border border-stone-200 bg-white/70 p-3">
      <div className="flex items-start justify-between gap-2">
        <div>
          <div className="text-[11px] font-semibold uppercase tracking-[0.18em] text-stone-400">{title}</div>
          <div className="mt-1 font-mono text-[11px] text-stone-500">{subtitle}</div>
        </div>
        <div className="mt-1 h-2.5 w-2.5 rounded-full" style={{ backgroundColor: color }} />
      </div>
      <SliceBars slices={slices} color={color} formatter={formatter} emptyLabel={emptyLabel} />
    </div>
  );
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
        <div className="font-mono">{sliceWindowLabel(data.slice_ms)}</div>
        <div className="font-mono">expired realtime {formatCount(data.bus.expired_realtime)}</div>
        <div className="font-mono">bus exceptions {formatCount(data.bus.exceptions)}</div>
      </div>
    </div>
  );
}

function MetricCard({ title, accent, summary, children }) {
  return (
    <section className="rounded-2xl border border-stone-200 bg-white/80 p-3">
      <div className="mb-3 flex items-center justify-between gap-2">
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

function TransactionCard({ title, accent, transaction, queue }) {
  return (
    <MetricCard
      title={title}
      accent={accent}
      summary={`latency last ${formatUs(transaction.last_latency_us)} • avg ${formatUs(transaction.avg_latency_us)}`}
    >
      <div className="grid gap-3 xl:grid-cols-2">
        <SliceMetric
          title="Latency"
          subtitle={`dispatches ${formatCount(transaction.dispatches)} • wkc ${formatCount(transaction.last_wkc)}`}
          slices={transaction.latency_slices}
          color={accent}
          formatter={formatUs}
          emptyLabel="No bus latency samples yet"
        />
        <SliceMetric
          title="Queue Depth"
          subtitle={`last ${formatCount(queue.last_depth)} • avg ${formatCount(queue.avg_depth)} • peak ${formatCount(queue.peak_depth)}`}
          slices={queue.slices}
          color="#475569"
          formatter={formatCount}
          emptyLabel="No queue samples yet"
        />
      </div>
      <div className="mt-3 grid grid-cols-2 gap-2 font-mono text-[11px] text-stone-500">
        <span>transactions {formatCount(transaction.transactions)}</span>
        <span>datagrams {formatCount(transaction.datagrams)}</span>
        <span>submissions {formatCount(transaction.count)}</span>
        <span>queue peak {formatCount(queue.peak_depth)}</span>
      </div>
    </MetricCard>
  );
}

function TransactionSection({ transactions, queues }) {
  return (
    <div className="grid gap-3 xl:grid-cols-2">
      <TransactionCard title="Realtime Bus" accent="#0f766e" transaction={transactions.realtime} queue={queues.realtime} />
      <TransactionCard title="Reliable Bus" accent="#1d4ed8" transaction={transactions.reliable} queue={queues.reliable} />
    </div>
  );
}

function FrameSection({ frames, links }) {
  return (
    <div className="grid gap-3 xl:grid-cols-[1.5fr_1fr]">
      <MetricCard
        title="Bus Frames"
        accent="#7c3aed"
        summary={`RTT last ${formatNs(frames.last_rtt_ns)} • peak ${formatNs(frames.peak_rtt_ns)}`}
      >
        <div className="grid gap-3 xl:grid-cols-2">
          <SliceMetric
            title="Round Trip"
            subtitle={`sent ${formatCount(frames.sent)} • received ${formatCount(frames.received)}`}
            slices={frames.rtt_slices}
            color="#7c3aed"
            formatter={formatNs}
            emptyLabel="No RTT samples yet"
          />
          <SliceMetric
            title="Sent / s"
            subtitle={`total ${formatCount(frames.sent)}`}
            slices={frames.sent_slices}
            color="#0f766e"
            formatter={formatCount}
            emptyLabel="No sent frames yet"
          />
          <SliceMetric
            title="Received / s"
            subtitle={`total ${formatCount(frames.received)}`}
            slices={frames.received_slices}
            color="#2563eb"
            formatter={formatCount}
            emptyLabel="No received frames yet"
          />
          <div className="space-y-3 rounded-2xl border border-stone-200 bg-white/70 p-3">
            <div>
              <div className="text-[11px] font-semibold uppercase tracking-[0.18em] text-stone-400">Fault Traffic</div>
              <div className="mt-1 font-mono text-[11px] text-stone-500">
                dropped {formatCount(frames.dropped)} • ignored {formatCount(frames.ignored)}
              </div>
            </div>
            <SliceMetric
              title="Dropped / s"
              subtitle={`expired ${formatCount(frames.expired_slices?.at(-1)?.value ?? 0)} • exceptions ${formatCount(frames.exception_slices?.at(-1)?.value ?? 0)}`}
              slices={frames.dropped_slices}
              color="#be123c"
              formatter={formatCount}
              emptyLabel="No dropped frames yet"
            />
            <div className="grid gap-3 lg:grid-cols-2">
              <SliceMetric
                title="Ignored / s"
                subtitle={`total ${formatCount(frames.ignored)}`}
                slices={frames.ignored_slices}
                color="#78716c"
                formatter={formatCount}
                emptyLabel="No ignored frames yet"
              />
              <SliceMetric
                title="Expired / s"
                subtitle={`exceptions ${formatCount(frames.exception_slices?.reduce((sum, slice) => sum + (slice.value ?? 0), 0) ?? 0)}`}
                slices={frames.expired_slices}
                color="#ea580c"
                formatter={formatCount}
                emptyLabel="No expired realtime work"
              />
            </div>
          </div>
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

      <div className="grid gap-3 xl:grid-cols-[1.15fr_1fr]">
        <div className="space-y-3">
          <SliceMetric
            title="Sync Diff / Slice"
            subtitle={`tick wkc ${formatCount(dc.tick_wkc)} • max ${formatNs(dc.max_sync_diff_ns)}`}
            slices={dc.sync_diff_slices}
            color="#be123c"
            formatter={formatNs}
            emptyLabel="No DC sync samples yet"
          />
          <div className="grid grid-cols-2 gap-2 font-mono text-[11px] text-stone-500">
            <span>configured {String(dc.configured)}</span>
            <span>active {String(dc.active)}</span>
            <span>cycle {formatNs(dc.cycle_ns)}</span>
            <span>failures {formatCount(dc.monitor_failures)}</span>
            <span>reference {dc.reference_clock ?? "n/a"}</span>
            <span>lock {dc.lock_state}</span>
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
              <div className="mt-3 grid gap-3 xl:grid-cols-2">
                <SliceMetric
                  title="Cycle Duration"
                  subtitle={`last ${formatUs(domain.last_cycle_us)} • avg ${formatUs(domain.avg_cycle_us)}`}
                  slices={domain.cycle_slices}
                  color="#d97706"
                  formatter={formatUs}
                  emptyLabel="No cycle telemetry yet"
                />
                <SliceMetric
                  title="Misses / Slice"
                  subtitle={`miss events ${formatCount(domain.missed_events)} • total misses ${formatCount(domain.total_miss_count)}`}
                  slices={domain.miss_slices}
                  color="#dc2626"
                  formatter={formatCount}
                  emptyLabel="No misses recorded"
                />
              </div>
              <div className="mt-3 grid grid-cols-2 gap-2 font-mono text-[11px] text-stone-500">
                <span>cycle {formatUs(domain.cycle_time_us)}</span>
                <span>wkc {formatCount(domain.expected_wkc)}</span>
                <span>miss count {formatCount(domain.miss_count)}</span>
                <span>miss reason {domain.last_miss_reason ?? "n/a"}</span>
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
