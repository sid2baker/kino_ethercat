import "./main.css";
import "uplot/dist/uPlot.min.css";

import React, { createContext, startTransition, useContext, useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import uPlot from "uplot";

import {
  Columns,
  DataTable,
  EmptyState,
  Inset,
  ModalShell,
  Mono,
  Panel,
  PropertyList,
  Stack,
  StatusBadge,
  SummaryGrid,
  Tab,
  Tabs,
} from "../../ui/react95";

const LayoutVersionContext = createContext(0);

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

function formatBytes(value) {
  if (value == null) return "n/a";

  if (Math.abs(value) >= 1_000_000) {
    return `${(value / 1_000_000).toFixed(1)} MB`;
  }

  if (Math.abs(value) >= 1_000) {
    return `${(value / 1_000).toFixed(1)} kB`;
  }

  return `${value.toLocaleString()} B`;
}

function formatHex(value, pad = 4) {
  if (value == null) return "n/a";
  return "0x" + (value >>> 0).toString(16).toUpperCase().padStart(pad, "0");
}

function formatTime(atMs) {
  if (!atMs) return "n/a";
  return new Date(atMs).toLocaleTimeString();
}

function sumSlices(slices = []) {
  return slices.reduce((sum, slice) => sum + (slice.value ?? 0), 0);
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
  const layoutVersion = useContext(LayoutVersionContext);
  const [ref, width] = useChartWidth();
  const seriesKey = series.map((entry) => `${entry.label}:${entry.stroke}:${entry.fill ?? ""}`).join("|");
  const options = useMemo(() => chartOptions(width, height, series, yUnit), [width, height, yUnit, seriesKey]);
  const data = buildChartData(series);

  return (
    <Inset className="ke95-diagnostics__chart-panel">
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
          <UPlotChart
            options={options}
            data={data}
            className="ke95-diagnostics__plot-root"
            chartKey={`${seriesKey}:${yUnit}:${layoutVersion}`}
          />
        ) : (
          <Inset className="ke95-chart__empty">
            <Mono>{emptyLabel}</Mono>
          </Inset>
        )}
      </div>
    </Inset>
  );
}

function SectionCopy({ children }) {
  if (!children) return null;
  return <div className="ke95-diagnostics__copy">{children}</div>;
}

function domainAlertCount(domains) {
  return domains.filter(
    (domain) =>
      domain.state !== "cycling" || domain.last_miss_reason || domain.stop_reason || domain.crash_reason
  ).length;
}

function nonOperationalSlaveCount(slaves) {
  return slaves.filter(
    (slave) => slave.al_state !== "op" || slave.al_error != null || slave.configuration_error
  ).length;
}

function slaveSummaryItems(slaves) {
  const counts = slaves.reduce(
    (acc, slave) => {
      const state = slave.al_state ?? "unknown";
      acc[state] = (acc[state] ?? 0) + 1;

      if (slave.al_error != null) {
        acc.al_errors += 1;
      }

      return acc;
    },
    { op: 0, safeop: 0, preop: 0, init: 0, unknown: 0, al_errors: 0 }
  );

  return [
    { label: "OP", value: formatCount(counts.op) },
    { label: "SAFEOP", value: formatCount(counts.safeop) },
    { label: "PREOP", value: formatCount(counts.preop) },
    { label: "INIT", value: formatCount(counts.init) },
    { label: "AL errors", value: formatCount(counts.al_errors) },
  ];
}

function Diagnostics({ ctx, data }) {
  const [snapshot, setSnapshot] = useState(data);
  const runtimeAlerts = domainAlertCount(snapshot.domains);
  const slaveAlerts = nonOperationalSlaveCount(snapshot.slaves);

  useEffect(() => {
    ctx.handleEvent("snapshot", (next) => {
      startTransition(() => setSnapshot(next));
    });
  }, [ctx]);

  return (
    <ModalShell
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
      {({ layoutVersion }) => (
        <LayoutVersionContext.Provider value={layoutVersion}>
          <Stack className="ke95-diagnostics">
            <SummaryGrid
              items={[
                { label: "Slice window", value: sliceWindowLabel(snapshot.slice_ms) },
                { label: "Slaves", value: String(snapshot.slaves.length) },
                { label: "Domains", value: String(snapshot.domains.length) },
                { label: "Bus exceptions", value: formatCount(snapshot.bus.exceptions) },
                { label: "Runtime alerts", value: formatCount(runtimeAlerts) },
                { label: "Slave alerts", value: formatCount(slaveAlerts) },
                { label: "Events", value: String(snapshot.timeline.length) },
              ]}
            />

            <Tabs defaultActiveTab="Overview">
              <Tab title="Overview">
                <OverviewSection snapshot={snapshot} runtimeAlerts={runtimeAlerts} slaveAlerts={slaveAlerts} />
              </Tab>
              <Tab title="Bus">
                <BusSection bus={snapshot.bus} />
              </Tab>
              <Tab title="Runtime">
                <RuntimeSection dc={snapshot.dc} domains={snapshot.domains} />
              </Tab>
              <Tab title="Slaves">
                <SlavesSection slaves={snapshot.slaves} />
              </Tab>
              <Tab title="Events">
                <TimelineSection timeline={snapshot.timeline} />
              </Tab>
            </Tabs>
          </Stack>
        </LayoutVersionContext.Provider>
      )}
    </ModalShell>
  );
}

function OverviewSection({ snapshot, runtimeAlerts, slaveAlerts }) {
  const latestEvents = snapshot.timeline.slice(0, 6);
  const unhealthyDomains = snapshot.domains.filter((domain) => domain.state !== "cycling").length;
  const downLinks = snapshot.bus.links.filter((link) => link.status === "down").length;

  return (
    <Stack>
      <Panel title="System overview">
        <Stack compact>
          <SectionCopy>Use this tab first. It keeps the current operating picture compact and readable.</SectionCopy>
          <SummaryGrid
            items={[
              { label: "Master", value: snapshot.state },
              { label: "DC lock", value: snapshot.dc?.lock_state ?? "disabled" },
              { label: "Unhealthy domains", value: formatCount(unhealthyDomains) },
              { label: "Slave alerts", value: formatCount(slaveAlerts) },
              { label: "Links down", value: formatCount(downLinks) },
              { label: "Last failure", value: snapshot.last_failure ?? "none" },
            ]}
          />
          <Columns minWidth="18rem">
            <PropertyList
              minWidth="12rem"
              items={[
                { label: "Realtime latency", value: formatUs(snapshot.bus.transactions.realtime.last_latency_us) },
                { label: "Reliable latency", value: formatUs(snapshot.bus.transactions.reliable.last_latency_us) },
                { label: "Expired RT", value: formatCount(snapshot.bus.expired_realtime) },
                { label: "Bus exceptions", value: formatCount(snapshot.bus.exceptions) },
              ]}
            />
            <PropertyList
              minWidth="12rem"
              items={[
                { label: "Domains", value: formatCount(snapshot.domains.length) },
                { label: "Runtime alerts", value: formatCount(runtimeAlerts) },
                { label: "Slaves", value: formatCount(snapshot.slaves.length) },
                { label: "Events", value: formatCount(snapshot.timeline.length) },
              ]}
            />
          </Columns>
        </Stack>
      </Panel>

      <Panel title="Latest events">
        {latestEvents.length === 0 ? (
          <EmptyState>No fault or recovery events yet</EmptyState>
        ) : (
          <Stack compact className="ke95-diagnostics__feed ke95-diagnostics__feed--overview">
            {latestEvents.map((event) => (
              <Inset key={event.id} className={`ke95-diagnostics__event ke95-diagnostics__event--${event.level}`}>
                <div className="ke95-toolbar">
                  <div>{event.title}</div>
                  <Mono>{formatTime(event.at_ms)}</Mono>
                </div>
                <Mono as="div">{event.detail}</Mono>
              </Inset>
            ))}
          </Stack>
        )}
      </Panel>
    </Stack>
  );
}

function BusSection({ bus }) {
  return (
    <Stack>
      <TransactionCard
        title="Realtime bus"
        accent="#0f766e"
        transaction={bus.transactions.realtime}
        queue={bus.queues.realtime}
      />
      <TransactionCard
        title="Reliable bus"
        accent="#1d4ed8"
        transaction={bus.transactions.reliable}
        queue={bus.queues.reliable}
      />
      <FrameSection frames={bus.frames} links={bus.links} />
    </Stack>
  );
}

function RuntimeSection({ dc, domains }) {
  return (
    <Stack>
      <DcSection dc={dc} />
      <DomainsSection domains={domains} />
    </Stack>
  );
}

function TransactionCard({ title, accent, transaction, queue }) {
  return (
    <Panel title={title}>
      <Stack compact>
        <Mono as="div">
          latency last {formatUs(transaction.last_latency_us)} • avg {formatUs(transaction.avg_latency_us)}
        </Mono>
        <Columns minWidth="22rem">
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
        </Columns>
        <SummaryGrid
          items={[
            { label: "Transactions", value: formatCount(transaction.transactions) },
            { label: "Datagrams", value: formatCount(transaction.datagrams) },
            { label: "Submissions", value: formatCount(transaction.count) },
            { label: "Queue peak", value: formatCount(queue.peak_depth) },
          ]}
        />
      </Stack>
    </Panel>
  );
}

function FrameSection({ frames, links }) {
  return (
    <Stack>
      <Panel title="Bus frames">
        <Stack compact>
          <Mono as="div">RTT last {formatNs(frames.last_rtt_ns)} • peak {formatNs(frames.peak_rtt_ns)}</Mono>
          <Columns minWidth="22rem">
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
            <ChartPanel
              title="Payload throughput"
              subtitle={`sent ${formatBytes(frames.sent_bytes)} • received ${formatBytes(frames.received_bytes)} • dropped ${formatBytes(frames.dropped_bytes)}`}
              series={[
                { label: "Sent", slices: frames.sent_bandwidth_slices, stroke: "#0f766e", fill: "#0f766e20" },
                { label: "Received", slices: frames.received_bandwidth_slices, stroke: "#2563eb", fill: "#2563eb20" },
                { label: "Dropped", slices: frames.dropped_bandwidth_slices, stroke: "#be123c", fill: "#be123c20" },
              ]}
              yUnit="B/s"
              emptyLabel="No payload throughput yet"
            />
          </Columns>
          <Columns minWidth="22rem">
            <ChartPanel
              title="Round trip"
              subtitle={`ignored ${formatCount(frames.ignored)} • exceptions ${formatCount(sumSlices(frames.exception_slices))}`}
              series={[{ label: "RTT", slices: frames.rtt_slices, stroke: "#7c3aed", fill: "#7c3aed20" }]}
              yUnit="ns"
              emptyLabel="No RTT samples yet"
            />
            <ChartPanel
              title="Fault timeline"
              subtitle={`expired realtime ${formatCount(sumSlices(frames.expired_slices))}`}
              series={[
                { label: "Expired", slices: frames.expired_slices, stroke: "#ea580c", fill: "#ea580c20" },
                { label: "Exceptions", slices: frames.exception_slices, stroke: "#dc2626", fill: "#dc262620" },
                { label: "Ignored", slices: frames.ignored_slices, stroke: "#78716c", fill: "#78716c20" },
              ]}
              emptyLabel="No bus faults recorded"
            />
          </Columns>
          <SummaryGrid
            items={[
              { label: "Sent payload", value: formatBytes(frames.sent_bytes) },
              { label: "Received payload", value: formatBytes(frames.received_bytes) },
              { label: "Dropped payload", value: formatBytes(frames.dropped_bytes) },
              { label: "Ignored frames", value: formatCount(frames.ignored) },
            ]}
          />
          {frames.dropped_reasons?.length ? (
            <PropertyList
              minWidth="12rem"
              items={frames.dropped_reasons.map((item) => ({
                label: item.reason,
                value: formatCount(item.count),
              }))}
            />
          ) : null}
        </Stack>
      </Panel>

      <Panel title="Links">
        {links.length === 0 ? (
          <EmptyState>No link telemetry yet</EmptyState>
        ) : (
          <Stack compact className="ke95-diagnostics__feed">
            {links.map((link) => (
              <Inset key={link.name} className="ke95-diagnostics__card">
                <div className="ke95-toolbar">
                  <Mono>{link.name}</Mono>
                  <StatusBadge tone={link.status === "down" ? "danger" : "ok"}>{link.status}</StatusBadge>
                </div>
                <Mono as="div">
                  {link.reason ? `${link.reason} • ` : ""}
                  {formatTime(link.at_ms)}
                </Mono>
              </Inset>
            ))}
          </Stack>
        )}
      </Panel>
    </Stack>
  );
}

function DcSection({ dc }) {
  return (
    <Panel title="Distributed clocks">
      <Stack compact>
        <SectionCopy>Clock lock matters when you want deterministic cycle timing and stable synchronization.</SectionCopy>
        <div className="ke95-toolbar">
          <StatusBadge tone={badgeTone(LOCK_TONES, dc.lock_state)}>{dc.lock_state}</StatusBadge>
        </div>

        <Columns minWidth="22rem">
          <ChartPanel
            title="Sync diff"
            subtitle={`tick wkc ${formatCount(dc.tick_wkc)} • max ${formatNs(dc.max_sync_diff_ns)}`}
            series={[{ label: "Sync diff", slices: dc.sync_diff_slices, stroke: "#be123c", fill: "#be123c20" }]}
            yUnit="ns"
            emptyLabel="No DC sync samples yet"
          />
          <PropertyList
            minWidth="12rem"
            items={[
              { label: "Configured", value: String(dc.configured) },
              { label: "Active", value: String(dc.active) },
              { label: "Cycle", value: formatNs(dc.cycle_ns) },
              { label: "Failures", value: formatCount(dc.monitor_failures) },
              { label: "Reference", value: dc.reference_clock ?? "n/a" },
              { label: "Lock", value: dc.lock_state },
            ]}
          />
        </Columns>
        {dc.lock_events?.length ? (
          <Stack compact className="ke95-diagnostics__feed">
            {dc.lock_events.slice().reverse().map((event, index) => (
              <Inset key={`${event.from}-${event.to}-${index}`} className="ke95-diagnostics__card">
                <Mono as="div">{event.from} → {event.to}</Mono>
                <Mono as="div">{formatNs(event.max_sync_diff_ns)}</Mono>
              </Inset>
            ))}
          </Stack>
        ) : (
          <EmptyState>No DC lock changes yet</EmptyState>
        )}
      </Stack>
    </Panel>
  );
}

function DomainsSection({ domains }) {
  return (
    <Panel title="Domains">
      {domains.length === 0 ? (
        <EmptyState>No domains running</EmptyState>
      ) : (
        <Stack>
          <SectionCopy>Domains show whether cyclic exchange is healthy and whether misses are accumulating.</SectionCopy>
          {domains.map((domain) => (
            <Inset key={domain.id} className="ke95-diagnostics__domain">
              <div className="ke95-toolbar">
                <Mono>{domain.id}</Mono>
                <StatusBadge tone={badgeTone(DOMAIN_TONES, domain.state)}>{domain.state}</StatusBadge>
              </div>
              <Columns minWidth="22rem">
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
              </Columns>
              <PropertyList
                minWidth="12rem"
                items={[
                  { label: "Cycle", value: formatUs(domain.cycle_time_us) },
                  { label: "WKC", value: formatCount(domain.expected_wkc) },
                  { label: "Miss count", value: formatCount(domain.miss_count) },
                  { label: "Total misses", value: formatCount(domain.total_miss_count) },
                  { label: "Miss reason", value: domain.last_miss_reason ?? "n/a" },
                ]}
              />
              {domain.last_miss_reason || domain.stop_reason || domain.crash_reason ? (
                <Inset className="ke95-diagnostics__event ke95-diagnostics__event--warn">
                  <Mono>
                    {domain.crash_reason
                      ? `crashed ${domain.crash_reason}`
                      : domain.stop_reason
                        ? `stopped ${domain.stop_reason}`
                        : `missed ${domain.last_miss_reason}`}
                  </Mono>
                </Inset>
              ) : null}
            </Inset>
          ))}
        </Stack>
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
        <Stack compact>
          <SectionCopy>Use this table to spot non-OP slaves, latched AL errors, and per-slave configuration issues.</SectionCopy>
          <SummaryGrid items={slaveSummaryItems(slaves)} />
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
        </Stack>
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
        <Stack compact>
          <SectionCopy>Keep this tab open when you want the full recovery story in time order.</SectionCopy>
          <Stack compact className="ke95-scroll ke95-diagnostics__feed">
            {timeline.map((event) => (
              <Inset key={event.id} className={`ke95-diagnostics__event ke95-diagnostics__event--${event.level}`}>
                <div className="ke95-toolbar">
                  <div>{event.title}</div>
                  <Mono>{formatTime(event.at_ms)}</Mono>
                </div>
                <Mono as="div">{event.detail}</Mono>
              </Inset>
            ))}
          </Stack>
        </Stack>
      )}
    </Panel>
  );
}
