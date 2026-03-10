import "./main.css";
import "uplot/dist/uPlot.min.css";

import React, { startTransition, useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import uPlot from "uplot";

import {
  DataTable,
  EmptyState,
  Frame,
  Mono,
  Panel,
  Shell,
  StatusBadge,
  SummaryGrid,
  Tab,
  Tabs,
} from "../../ui/react95";

export async function init(ctx, data) {
  await ctx.importCSS("main.css");
  const root = createRoot(ctx.root);
  root.render(<Diagnostics ctx={ctx} data={data} />);
}

const STATE_TONES = {
  idle: "neutral",
  discovering: "warn",
  awaiting_preop: "warn",
  preop_ready: "warn",
  operational: "ok",
  activation_blocked: "danger",
  recovering: "warn",
};

const DOMAIN_TONES = {
  cycling: "ok",
  open: "warn",
  stopped: "danger",
  unknown: "neutral",
};

const LOCK_TONES = {
  locked: "ok",
  locking: "warn",
  unavailable: "neutral",
  inactive: "warn",
  disabled: "neutral",
};

const SLAVE_TONES = {
  op: "ok",
  safeop: "warn",
  preop: "warn",
  init: "neutral",
  unknown: "neutral",
};

function badgeTone(styles, key) {
  return styles[key] ?? "neutral";
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

function axisTime(value) {
  return new Date(value * 1000).toLocaleTimeString([], {
    hour12: false,
    minute: "2-digit",
    second: "2-digit",
  });
}

function axisCompact(value, unit = "") {
  if (!Number.isFinite(value)) return "";

  if (Math.abs(value) >= 1_000_000) {
    return `${(value / 1_000_000).toFixed(1)}M${unit}`;
  }

  if (Math.abs(value) >= 1_000) {
    return `${(value / 1_000).toFixed(1)}k${unit}`;
  }

  return `${Math.round(value)}${unit}`;
}

function useChartWidth(minWidth = 280) {
  const ref = useRef(null);
  const [width, setWidth] = useState(minWidth);

  useEffect(() => {
    const element = ref.current;
    if (!element) return undefined;

    const update = () => {
      const nextWidth = Math.max(Math.floor(element.clientWidth) - 8, minWidth);
      setWidth(nextWidth);
    };

    update();

    if (typeof ResizeObserver === "undefined") return undefined;

    const observer = new ResizeObserver(update);
    observer.observe(element);

    return () => observer.disconnect();
  }, [minWidth]);

  return [ref, width];
}

function buildChartData(series) {
  const first = series.find((entry) => entry.slices && entry.slices.length > 0);
  if (!first) return null;

  const timestamps = first.slices.map((slice) => slice.at_ms / 1000);

  return [
    timestamps,
    ...series.map((entry) => {
      const byTimestamp = new Map(entry.slices.map((slice) => [slice.at_ms, slice.value ?? 0]));
      return first.slices.map((slice) => byTimestamp.get(slice.at_ms) ?? 0);
    }),
  ];
}

function positiveRange(_u, min, max) {
  if (!Number.isFinite(min) || !Number.isFinite(max)) {
    return [0, 1];
  }

  const nextMax = max <= 0 ? 1 : max * 1.1;
  return [0, nextMax];
}

function chartOptions(width, height, series, yUnit = "") {
  return {
    width,
    height,
    padding: [10, 8, 4, 4],
    legend: { show: false },
    cursor: {
      drag: {
        setScale: false,
        x: false,
        y: false,
      },
    },
    scales: {
      x: { time: true },
      y: { auto: true, range: positiveRange },
    },
    axes: [
      {
        stroke: "#606060",
        grid: { stroke: "#d0d0d0" },
        values: (_u, splits) => splits.map(axisTime),
      },
      {
        stroke: "#606060",
        grid: { stroke: "#d0d0d0" },
        values: (_u, splits) => splits.map((value) => axisCompact(value, yUnit)),
      },
    ],
    series: [
      {},
      ...series.map((entry) => ({
        label: entry.label,
        stroke: entry.stroke,
        width: 2,
        fill: entry.fill,
        points: { show: false },
        value: (_u, value) => (value == null ? "n/a" : `${value}`),
      })),
    ],
  };
}

function UPlotChart({ options, data, className, chartKey }) {
  const targetRef = useRef(null);
  const chartRef = useRef(null);

  useEffect(() => {
    if (!targetRef.current || !data) return undefined;

    const chart = new uPlot(options, data, targetRef.current);
    chartRef.current = chart;

    return () => {
      chart.destroy();
      chartRef.current = null;
    };
  }, [chartKey]);

  useEffect(() => {
    if (chartRef.current && data) {
      chartRef.current.setData(data, true);
    }
  }, [data]);

  useEffect(() => {
    if (chartRef.current) {
      chartRef.current.setSize({ width: options.width, height: options.height });
    }
  }, [options.width, options.height]);

  return <div ref={targetRef} className={className} />;
}

function ChartPanel({ title, subtitle, series, height = 210, yUnit = "", emptyLabel = "No samples yet" }) {
  const [ref, width] = useChartWidth();
  const seriesKey = series.map((entry) => `${entry.label}:${entry.stroke}:${entry.fill ?? ""}`).join("|");
  const options = useMemo(() => chartOptions(width, height, series, yUnit), [width, height, yUnit, seriesKey]);
  const data = buildChartData(series);

  return (
    <Frame boxShadow="in" className="ke95-diagnostics__chart-panel">
      <div className="ke95-diagnostics__chart-copy">
        <div className="ke95-kicker">{title}</div>
        <Mono as="div">{subtitle}</Mono>
      </div>

      <div className="ke95-diagnostics__legend">
        {series.map((entry) => (
          <span key={entry.label} className="ke95-diagnostics__legend-item">
            <span className="ke95-diagnostics__legend-swatch" style={{ backgroundColor: entry.stroke }} />
            <Mono>{entry.label}</Mono>
          </span>
        ))}
      </div>

      <div ref={ref} className="ke95-chart">
        {data ? (
          <UPlotChart options={options} data={data} className="ke95-diagnostics__plot-root" chartKey={`${seriesKey}:${yUnit}`} />
        ) : (
          <Frame boxShadow="in" className="ke95-chart__empty">
            <Mono>{emptyLabel}</Mono>
          </Frame>
        )}
      </div>
    </Frame>
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
    <Shell
      title="Master diagnostics"
      subtitle={snapshot.last_failure ? `last failure ${snapshot.last_failure}` : "no recorded master failure"}
      status={
        <>
          <StatusBadge tone={badgeTone(STATE_TONES, snapshot.state)}>{snapshot.state}</StatusBadge>
          <StatusBadge tone={badgeTone(LOCK_TONES, snapshot.dc?.lock_state ?? "disabled")}>
            {snapshot.dc?.lock_state ?? "disabled"}
          </StatusBadge>
        </>
      }
    >
      <SummaryGrid
        items={[
          { label: "Slice window", value: sliceWindowLabel(snapshot.slice_ms) },
          { label: "Expired RT", value: formatCount(snapshot.bus.expired_realtime) },
          { label: "Bus exceptions", value: formatCount(snapshot.bus.exceptions) },
          { label: "Slaves", value: String(snapshot.slaves.length) },
          { label: "Domains", value: String(snapshot.domains.length) },
          { label: "DC state", value: snapshot.dc?.lock_state ?? "disabled" },
        ]}
      />

      <Tabs defaultActiveTab="Performance">
        <Tab title="Performance">
          <div className="ke95-grid">
            <div className="ke95-grid ke95-grid--2">
              <TransactionCard title="Realtime bus" accent="#0f766e" transaction={snapshot.bus.transactions.realtime} queue={snapshot.bus.queues.realtime} />
              <TransactionCard title="Reliable bus" accent="#1d4ed8" transaction={snapshot.bus.transactions.reliable} queue={snapshot.bus.queues.reliable} />
            </div>
            <FrameSection frames={snapshot.bus.frames} links={snapshot.bus.links} />
            <DcSection dc={snapshot.dc} />
          </div>
        </Tab>
        <Tab title="Domains">
          <DomainsSection domains={snapshot.domains} />
        </Tab>
        <Tab title="Slaves">
          <SlavesSection slaves={snapshot.slaves} />
        </Tab>
        <Tab title="Events">
          <TimelineSection timeline={snapshot.timeline} />
        </Tab>
      </Tabs>
    </Shell>
  );
}

function TransactionCard({ title, accent, transaction, queue }) {
  return (
    <Panel title={title}>
      <Mono as="div">
        latency last {formatUs(transaction.last_latency_us)} • avg {formatUs(transaction.avg_latency_us)}
      </Mono>
      <div className="ke95-grid ke95-grid--2">
        <ChartPanel
          title="Latency"
          subtitle={`dispatches ${formatCount(transaction.dispatches)} • wkc ${formatCount(transaction.last_wkc)}`}
          series={[{ label: "Latency", slices: transaction.latency_slices, stroke: accent, fill: `${accent}26` }]}
          yUnit="us"
          emptyLabel="No bus latency samples yet"
        />
        <ChartPanel
          title="Queue depth"
          subtitle={`last ${formatCount(queue.last_depth)} • avg ${formatCount(queue.avg_depth)} • peak ${formatCount(queue.peak_depth)}`}
          series={[{ label: "Queue", slices: queue.slices, stroke: "#475569", fill: "#47556926" }]}
          emptyLabel="No queue samples yet"
        />
      </div>
      <SummaryGrid
        items={[
          { label: "Transactions", value: formatCount(transaction.transactions) },
          { label: "Datagrams", value: formatCount(transaction.datagrams) },
          { label: "Submissions", value: formatCount(transaction.count) },
          { label: "Queue peak", value: formatCount(queue.peak_depth) },
        ]}
      />
    </Panel>
  );
}

function FrameSection({ frames, links }) {
  return (
    <div className="ke95-grid ke95-grid--2">
      <Panel title="Bus frames">
        <Mono as="div">RTT last {formatNs(frames.last_rtt_ns)} • peak {formatNs(frames.peak_rtt_ns)}</Mono>
        <ChartPanel
          title="Traffic"
          subtitle={`sent ${formatCount(frames.sent)} • received ${formatCount(frames.received)} • dropped ${formatCount(frames.dropped)}`}
          series={[
            { label: "Sent", slices: frames.sent_slices, stroke: "#0f766e", fill: "#0f766e20" },
            { label: "Received", slices: frames.received_slices, stroke: "#2563eb", fill: "#2563eb20" },
            { label: "Dropped", slices: frames.dropped_slices, stroke: "#be123c", fill: "#be123c20" },
          ]}
          emptyLabel="No frame traffic yet"
        />
        <div className="ke95-grid ke95-grid--2">
          <ChartPanel
            title="Round trip"
            subtitle={`ignored ${formatCount(frames.ignored)} • exceptions ${formatCount(frames.exception_slices.reduce((sum, slice) => sum + (slice.value ?? 0), 0))}`}
            series={[{ label: "RTT", slices: frames.rtt_slices, stroke: "#7c3aed", fill: "#7c3aed20" }]}
            yUnit="ns"
            emptyLabel="No RTT samples yet"
          />
          <ChartPanel
            title="Fault timeline"
            subtitle={`expired realtime ${formatCount(frames.expired_slices.reduce((sum, slice) => sum + (slice.value ?? 0), 0))}`}
            series={[
              { label: "Expired", slices: frames.expired_slices, stroke: "#ea580c", fill: "#ea580c20" },
              { label: "Exceptions", slices: frames.exception_slices, stroke: "#dc2626", fill: "#dc262620" },
              { label: "Ignored", slices: frames.ignored_slices, stroke: "#78716c", fill: "#78716c20" },
            ]}
            emptyLabel="No bus faults recorded"
          />
        </div>
      </Panel>

      <Panel title="Links">
        {links.length === 0 ? (
          <EmptyState>No link telemetry yet</EmptyState>
        ) : (
          <div className="ke95-grid">
            {links.map((link) => (
              <Frame key={link.name} boxShadow="in" className="ke95-diagnostics__card">
                <div className="ke95-toolbar">
                  <Mono>{link.name}</Mono>
                  <StatusBadge tone={link.status === "down" ? "danger" : "ok"}>{link.status}</StatusBadge>
                </div>
                <Mono as="div">
                  {link.reason ? `${link.reason} • ` : ""}
                  {formatTime(link.at_ms)}
                </Mono>
              </Frame>
            ))}
          </div>
        )}
      </Panel>
    </div>
  );
}

function DcSection({ dc }) {
  return (
    <Panel title="Distributed clocks">
      <div className="ke95-toolbar">
        <StatusBadge tone={badgeTone(LOCK_TONES, dc.lock_state)}>{dc.lock_state}</StatusBadge>
      </div>

      <div className="ke95-grid ke95-grid--2">
        <div className="ke95-grid">
          <ChartPanel
            title="Sync diff"
            subtitle={`tick wkc ${formatCount(dc.tick_wkc)} • max ${formatNs(dc.max_sync_diff_ns)}`}
            series={[{ label: "Sync diff", slices: dc.sync_diff_slices, stroke: "#be123c", fill: "#be123c20" }]}
            yUnit="ns"
            emptyLabel="No DC sync samples yet"
          />
          <SummaryGrid
            items={[
              { label: "Configured", value: String(dc.configured) },
              { label: "Active", value: String(dc.active) },
              { label: "Cycle", value: formatNs(dc.cycle_ns) },
              { label: "Failures", value: formatCount(dc.monitor_failures) },
              { label: "Reference", value: dc.reference_clock ?? "n/a" },
              { label: "Lock", value: dc.lock_state },
            ]}
          />
        </div>

        {dc.lock_events?.length ? (
          <div className="ke95-grid">
            {dc.lock_events.slice().reverse().map((event, index) => (
              <Frame key={`${event.from}-${event.to}-${index}`} boxShadow="in" className="ke95-diagnostics__card">
                <Mono as="div">{event.from} → {event.to}</Mono>
                <Mono as="div">{formatNs(event.max_sync_diff_ns)}</Mono>
              </Frame>
            ))}
          </div>
        ) : (
          <EmptyState>No DC lock changes yet</EmptyState>
        )}
      </div>
    </Panel>
  );
}

function DomainsSection({ domains }) {
  return (
    <Panel title="Domains">
      {domains.length === 0 ? (
        <EmptyState>No domains running</EmptyState>
      ) : (
        <div className="ke95-grid ke95-grid--2">
          {domains.map((domain) => (
            <Frame key={domain.id} boxShadow="in" className="ke95-diagnostics__domain">
              <div className="ke95-toolbar">
                <Mono>{domain.id}</Mono>
                <StatusBadge tone={badgeTone(DOMAIN_TONES, domain.state)}>{domain.state}</StatusBadge>
              </div>
              <div className="ke95-grid">
                <ChartPanel
                  title="Cycle duration"
                  subtitle={`last ${formatUs(domain.last_cycle_us)} • avg ${formatUs(domain.avg_cycle_us)}`}
                  series={[{ label: "Cycle", slices: domain.cycle_slices, stroke: "#d97706", fill: "#d9770620" }]}
                  yUnit="us"
                  emptyLabel="No cycle telemetry yet"
                />
                <ChartPanel
                  title="Misses"
                  subtitle={`miss events ${formatCount(domain.missed_events)} • total misses ${formatCount(domain.total_miss_count)}`}
                  series={[{ label: "Misses", slices: domain.miss_slices, stroke: "#dc2626", fill: "#dc262620" }]}
                  emptyLabel="No misses recorded"
                />
              </div>
              <SummaryGrid
                items={[
                  { label: "Cycle", value: formatUs(domain.cycle_time_us) },
                  { label: "WKC", value: formatCount(domain.expected_wkc) },
                  { label: "Miss count", value: formatCount(domain.miss_count) },
                  { label: "Miss reason", value: domain.last_miss_reason ?? "n/a" },
                ]}
              />
              {domain.last_miss_reason || domain.stop_reason || domain.crash_reason ? (
                <Frame boxShadow="in" className="ke95-diagnostics__event ke95-diagnostics__event--warn">
                  <Mono>
                    {domain.crash_reason
                      ? `crashed ${domain.crash_reason}`
                      : domain.stop_reason
                        ? `stopped ${domain.stop_reason}`
                        : `missed ${domain.last_miss_reason}`}
                  </Mono>
                </Frame>
              ) : null}
            </Frame>
          ))}
        </div>
      )}
    </Panel>
  );
}

function SlavesSection({ slaves }) {
  return (
    <Panel title="Slaves">
      {slaves.length === 0 ? (
        <EmptyState>No slaves running</EmptyState>
      ) : (
        <DataTable headers={["Name", "Station", "State", "AL", "Config", "Event"]}>
          {slaves.map((slave) => (
            <tr key={slave.name}>
              <td><Mono>{slave.name}</Mono></td>
              <td><Mono>{slave.station != null ? formatHex(slave.station) : "n/a"}</Mono></td>
              <td><StatusBadge tone={badgeTone(SLAVE_TONES, slave.al_state)}>{slave.al_state}</StatusBadge></td>
              <td><Mono>{slave.al_error != null ? formatHex(slave.al_error) : "n/a"}</Mono></td>
              <td><Mono>{slave.configuration_error ?? "n/a"}</Mono></td>
              <td><Mono>{slave.last_event ? `${slave.last_event.title} • ${formatTime(slave.last_event.at_ms)}` : "n/a"}</Mono></td>
            </tr>
          ))}
        </DataTable>
      )}
    </Panel>
  );
}

function TimelineSection({ timeline }) {
  return (
    <Panel title="Event timeline">
      {timeline.length === 0 ? (
        <EmptyState>No fault or recovery events yet</EmptyState>
      ) : (
        <div className="ke95-scroll ke95-grid">
          {timeline.map((event) => (
            <Frame key={event.id} boxShadow="in" className={`ke95-diagnostics__event ke95-diagnostics__event--${event.level}`}>
              <div className="ke95-toolbar">
                <div>{event.title}</div>
                <Mono>{formatTime(event.at_ms)}</Mono>
              </div>
              <Mono as="div">{event.detail}</Mono>
            </Frame>
          ))}
        </div>
      )}
    </Panel>
  );
}
