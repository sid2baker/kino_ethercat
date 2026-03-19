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
  deactivated: "warn",
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

const DC_RUNTIME_TONES = {
  healthy: "ok",
  failing: "danger",
};

const RESULT_TONES = {
  ok: "ok",
  blocked: "warn",
  error: "danger",
  unknown: "neutral",
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

function formatMs(value) {
  if (value == null) return "n/a";
  return `${value.toLocaleString()} ms`;
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

function formatSnapshotTime(atMs) {
  if (!atMs) return "n/a";

  return new Date(atMs).toLocaleTimeString([], {
    hour12: false,
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
}

function formatBoolean(value) {
  if (value == null) return "n/a";
  return value ? "yes" : "no";
}

function formatResult(result) {
  if (!result) return "not run";
  return result.status ?? "n/a";
}

function formatLinkTime(atMs) {
  if (!atMs) return "never";
  return formatTime(atMs);
}

function masterStateEventLevel(state) {
  if (state === "activation_blocked") return "danger";
  if (state === "recovering") return "warn";
  return "info";
}

function masterStateChangeTitle(change) {
  if (change.from === change.to) return `Stayed ${change.to}`;
  if (change.from === "recovering" && change.to === "operational") return "Recovered to operational";
  return `Entered ${change.to}`;
}

function masterStateChangeDetail(change) {
  return [
    `${change.from} -> ${change.to}`,
    change.runtime_target ? `target ${change.runtime_target}` : null,
    change.cause ? `cause ${change.cause}` : null,
  ]
    .filter(Boolean)
    .join(" • ");
}

function cycleHealthState(cycleHealth) {
  if (!cycleHealth) return "unknown";
  if (typeof cycleHealth === "string") return cycleHealth;
  if (typeof cycleHealth === "object") return cycleHealth.state ?? "unknown";
  return String(cycleHealth);
}

function cycleHealthDetail(cycleHealth) {
  if (!cycleHealth || typeof cycleHealth !== "object") return null;
  return cycleHealth.detail ?? null;
}

function formatCycleHealth(cycleHealth) {
  const state = cycleHealthState(cycleHealth);
  const detail = cycleHealthDetail(cycleHealth);
  return detail ? `${state} • ${detail}` : state;
}

function healthTone(cycleHealth) {
  const state = cycleHealthState(cycleHealth);
  if (state === "healthy") return "ok";
  if (state.startsWith("transport_miss")) return "danger";
  if (state.startsWith("invalid")) return "warn";
  return "neutral";
}

function formatWkcContext(domain) {
  if (domain.last_transport_miss?.actual_wkc != null || domain.last_transport_miss?.expected_wkc != null) {
    return `${domain.last_transport_miss.actual_wkc ?? "?"} / ${domain.last_transport_miss.expected_wkc ?? "?"}`;
  }

  if (domain.last_invalid?.actual_wkc != null || domain.last_invalid?.expected_wkc != null) {
    return `${domain.last_invalid.actual_wkc ?? "?"} / ${domain.last_invalid.expected_wkc ?? "?"}`;
  }

  if (domain.expected_wkc != null) return formatCount(domain.expected_wkc);
  return "n/a";
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

function EventFeed({ items, emptyLabel = "No events yet", compact = false }) {
  if (!items || items.length === 0) {
    return <EmptyState>{emptyLabel}</EmptyState>;
  }

  return (
    <Stack compact className={`ke95-diagnostics__feed${compact ? " ke95-diagnostics__feed--overview" : ""}`}>
      {items.map((item, index) => (
        <Inset key={item.id ?? `${item.title}-${item.at_ms ?? index}-${index}`} className="ke95-diagnostics__event">
          <div className="ke95-toolbar">
            <div>{item.title}</div>
            <Mono>{formatTime(item.at_ms)}</Mono>
          </div>
          <Mono as="div">{item.detail}</Mono>
        </Inset>
      ))}
    </Stack>
  );
}

function latestSliceValue(slices = []) {
  return slices.length ? slices[slices.length - 1].value ?? 0 : 0;
}

function issueRank(level) {
  switch (level) {
    case "danger":
      return 3;
    case "warn":
      return 2;
    case "info":
      return 1;
    default:
      return 0;
  }
}

function sortIssues(items) {
  return [...items].sort(
    (left, right) =>
      issueRank(right.level) - issueRank(left.level) ||
      (right.at_ms ?? 0) - (left.at_ms ?? 0) ||
      left.title.localeCompare(right.title)
  );
}

function formatWkcPair(actual, expected) {
  if (actual == null && expected == null) return null;
  return `WKC ${actual ?? "?"}/${expected ?? "?"}`;
}

function domainIssueDetail(domain) {
  const parts = [];
  const transportMiss = domain.last_transport_miss;
  const invalid = domain.last_invalid;
  const latestIssue = transportMiss ?? invalid;
  const health = formatCycleHealth(domain.cycle_health);

  if (health !== "healthy") {
    parts.push(health);
  }

  const wkc = latestIssue ? formatWkcPair(latestIssue.actual_wkc, latestIssue.expected_wkc) : null;
  if (wkc) parts.push(wkc);
  if (transportMiss?.consecutive_miss_count != null) parts.push(`misses ${transportMiss.consecutive_miss_count}`);
  if (domain.last_cycle_us != null) parts.push(`cycle ${formatUs(domain.last_cycle_us)}`);

  return parts.join(" • ") || "current domain issue";
}

function domainCurrentIssue(domain) {
  if (domain.crash_reason) {
    return {
      id: `domain-${domain.id}-crash`,
      scope: "domain",
      level: "danger",
      title: `Domain ${domain.id} crashed`,
      detail: domain.crash_reason,
    };
  }

  if (domain.stop_reason || domain.state === "stopped") {
    return {
      id: `domain-${domain.id}-stop`,
      scope: "domain",
      level: "danger",
      title: `Domain ${domain.id} stopped`,
      detail: domain.stop_reason ?? domainIssueDetail(domain),
    };
  }

  const health = cycleHealthState(domain.cycle_health);

  if (health.startsWith("transport_miss")) {
    return {
      id: `domain-${domain.id}-transport-miss`,
      scope: "domain",
      level: "danger",
      title: `Domain ${domain.id} transport miss`,
      detail: domainIssueDetail(domain),
      at_ms: domain.last_transport_miss?.at_ms,
    };
  }

  if (health !== "healthy" && health !== "unknown") {
    return {
      id: `domain-${domain.id}-invalid`,
      scope: "domain",
      level: "warn",
      title: `Domain ${domain.id} invalid`,
      detail: domainIssueDetail(domain),
      at_ms: domain.last_invalid?.at_ms,
    };
  }

  if (domain.state !== "cycling" && domain.state !== "unknown") {
    return {
      id: `domain-${domain.id}-state`,
      scope: "domain",
      level: "warn",
      title: `Domain ${domain.id} is ${domain.state}`,
      detail: domainIssueDetail(domain),
    };
  }

  return null;
}

function slaveCurrentIssue(slave) {
  if (slave.configuration_error) {
    return {
      id: `slave-${slave.name}-config`,
      scope: "slave",
      level: "danger",
      title: `Slave ${slave.name} configuration error`,
      detail: slave.configuration_error,
      at_ms: slave.last_event?.at_ms,
    };
  }

  if (slave.fault) {
    return {
      id: `slave-${slave.name}-fault`,
      scope: "slave",
      level: "danger",
      title: `Slave ${slave.name} fault`,
      detail: slave.fault,
      at_ms: slave.last_event?.at_ms,
    };
  }

  if (slave.al_error != null) {
    return {
      id: `slave-${slave.name}-al-error`,
      scope: "slave",
      level: "warn",
      title: `Slave ${slave.name} AL error`,
      detail: `${formatHex(slave.al_error)} • state ${slave.al_state ?? "unknown"}`,
      at_ms: slave.last_event?.at_ms,
    };
  }

  if (slave.al_state !== "op" && slave.al_state !== "unknown") {
    return {
      id: `slave-${slave.name}-state`,
      scope: "slave",
      level: "warn",
      title: `Slave ${slave.name} is ${slave.al_state}`,
      detail: slave.last_event?.detail ?? "not in OP",
      at_ms: slave.last_event?.at_ms,
    };
  }

  return null;
}

function masterCurrentIssues(snapshot) {
  const issues = [];

  if (snapshot.state === "recovering") {
    issues.push({
      id: "master-recovering",
      scope: "master",
      level: "danger",
      title: "Master recovering",
      detail: [`target ${snapshot.master.runtime_target ?? "n/a"}`, snapshot.last_failure].filter(Boolean).join(" • "),
    });
  } else if (snapshot.state === "activation_blocked") {
    issues.push({
      id: "master-activation-blocked",
      scope: "master",
      level: "danger",
      title: "Master activation blocked",
      detail: [`target ${snapshot.master.runtime_target ?? "n/a"}`, snapshot.master.activation_result?.reason].filter(Boolean).join(" • "),
    });
  } else if (!["operational", "idle"].includes(snapshot.state)) {
    issues.push({
      id: `master-${snapshot.state}`,
      scope: "master",
      level: "warn",
      title: `Master ${snapshot.state}`,
      detail: [`target ${snapshot.master.runtime_target ?? "n/a"}`, snapshot.last_failure].filter(Boolean).join(" • "),
    });
  }

  if (snapshot.master.configuration_result?.status === "error") {
    issues.push({
      id: "master-configuration-error",
      scope: "master",
      level: "danger",
      title: "Configuration failed",
      detail: [formatMs(snapshot.master.configuration_result.duration_ms), snapshot.master.configuration_result.reason].filter(Boolean).join(" • "),
      at_ms: snapshot.master.configuration_result.at_ms,
    });
  }

  if (snapshot.master.activation_result?.status === "error") {
    issues.push({
      id: "master-activation-error",
      scope: "master",
      level: "danger",
      title: "Activation failed",
      detail: [formatMs(snapshot.master.activation_result.duration_ms), snapshot.master.activation_result.reason].filter(Boolean).join(" • "),
      at_ms: snapshot.master.activation_result.at_ms,
    });
  } else if (snapshot.master.activation_result?.status === "blocked") {
    issues.push({
      id: "master-activation-blocked-result",
      scope: "master",
      level: "warn",
      title: "Activation blocked",
      detail: [`blocked ${formatCount(snapshot.master.activation_result.blocked_count)}`, snapshot.master.activation_result.reason].filter(Boolean).join(" • "),
      at_ms: snapshot.master.activation_result.at_ms,
    });
  }

  return issues;
}

function dcCurrentIssues(dc) {
  if (!dc) return [];

  const issues = [];

  if (dc.runtime_state === "failing") {
    issues.push({
      id: "dc-runtime-failing",
      scope: "dc",
      level: "danger",
      title: "Distributed clocks failing",
      detail: [dc.runtime_reason, `failures ${formatCount(dc.consecutive_failures)}`, formatNs(dc.max_sync_diff_ns)].filter((value) => value && value !== "n/a").join(" • "),
    });
  }

  if (dc.configured && dc.active && !["locked", "disabled"].includes(dc.lock_state)) {
    issues.push({
      id: "dc-lock-not-locked",
      scope: "dc",
      level: "warn",
      title: `DC lock ${dc.lock_state}`,
      detail: [formatNs(dc.max_sync_diff_ns), dc.reference_clock, dc.reference_station != null ? formatHex(dc.reference_station) : null].filter((value) => value && value !== "n/a").join(" • "),
    });
  }

  return issues;
}

function busCurrentIssues(bus, sliceMs) {
  const issues = [];
  const droppedNow = latestSliceValue(bus.frames.dropped_slices);
  const exceptionsNow = latestSliceValue(bus.frames.exception_slices);
  const expiredNow = latestSliceValue(bus.frames.expired_slices);
  const sliceLabel = sliceWindowLabel(sliceMs);

  bus.links
    .filter((link) => link.status === "down")
    .forEach((link) => {
      issues.push({
        id: `link-${link.name}-down`,
        scope: "bus",
        level: "danger",
        title: `Link ${link.name} down`,
        detail: [link.endpoint, link.reason, formatLinkTime(link.at_ms)].filter(Boolean).join(" • "),
        at_ms: link.at_ms,
      });
    });

  if (droppedNow > 0) {
    issues.push({
      id: "bus-dropped-now",
      scope: "bus",
      level: "danger",
      title: "Frames dropped recently",
      detail: [`${formatCount(droppedNow)} in latest ${sliceLabel}`, bus.frames.dropped_reasons?.[0]?.reason].filter(Boolean).join(" • "),
    });
  }

  if (expiredNow > 0) {
    issues.push({
      id: "bus-expired-now",
      scope: "bus",
      level: "warn",
      title: "Realtime submissions expired",
      detail: `${formatCount(expiredNow)} in latest ${sliceLabel}`,
    });
  }

  if (exceptionsNow > 0) {
    issues.push({
      id: "bus-exceptions-now",
      scope: "bus",
      level: "warn",
      title: "Bus exceptions observed",
      detail: `${formatCount(exceptionsNow)} in latest ${sliceLabel}`,
    });
  }

  return issues;
}

function decorateDomains(domains) {
  return [...domains]
    .map((domain) => ({ ...domain, current_issue: domainCurrentIssue(domain) }))
    .sort(
      (left, right) =>
        issueRank(right.current_issue?.level) - issueRank(left.current_issue?.level) ||
        left.id.localeCompare(right.id)
    );
}

function decorateSlaves(slaves) {
  return [...slaves]
    .map((slave) => ({ ...slave, current_issue: slaveCurrentIssue(slave) }))
    .sort(
      (left, right) =>
        issueRank(right.current_issue?.level) - issueRank(left.current_issue?.level) ||
        left.name.localeCompare(right.name)
    );
}

function slaveSummaryItems(slaves) {
  const counts = slaves.reduce(
    (acc, slave) => {
      const state = slave.al_state ?? "unknown";
      acc[state] = (acc[state] ?? 0) + 1;

      if (slave.al_error != null) acc.al_errors += 1;
      if (slave.fault) acc.faults += 1;

      return acc;
    },
    { op: 0, safeop: 0, preop: 0, init: 0, unknown: 0, al_errors: 0, faults: 0 }
  );

  return [
    { label: "OP", value: formatCount(counts.op) },
    { label: "SAFEOP", value: formatCount(counts.safeop) },
    { label: "PREOP", value: formatCount(counts.preop) },
    { label: "INIT", value: formatCount(counts.init) },
    { label: "Faults", value: formatCount(counts.faults) },
    { label: "AL errors", value: formatCount(counts.al_errors) },
  ];
}

function domainSummaryItems(domains) {
  const counts = domains.reduce(
    (acc, domain) => {
      const issue = domain.current_issue;
      acc.total += 1;

      if (!issue) {
        acc.healthy += 1;
      } else if (issue.level === "danger") {
        acc.danger += 1;
      } else {
        acc.warn += 1;
      }

      if (cycleHealthState(domain.cycle_health).startsWith("transport_miss")) acc.transport += 1;
      if (cycleHealthState(domain.cycle_health) === "invalid") acc.invalid += 1;
      if (domain.stop_reason || domain.crash_reason || domain.state === "stopped") acc.stopped += 1;

      return acc;
    },
    { total: 0, healthy: 0, warn: 0, danger: 0, invalid: 0, transport: 0, stopped: 0 }
  );

  return [
    { label: "Healthy", value: formatCount(counts.healthy) },
    { label: "Warn", value: formatCount(counts.warn) },
    { label: "Danger", value: formatCount(counts.danger) },
    { label: "Invalid", value: formatCount(counts.invalid) },
    { label: "Transport miss", value: formatCount(counts.transport) },
    { label: "Stopped", value: formatCount(counts.stopped) },
  ];
}

function IssueList({ items, emptyLabel = "No active issues", className = "" }) {
  if (!items.length) {
    return <EmptyState>{emptyLabel}</EmptyState>;
  }

  return (
    <Stack compact className={`ke95-diagnostics__feed ke95-diagnostics__feed--overview ${className}`.trim()}>
      {items.map((item) => (
        <Inset key={item.id} className="ke95-diagnostics__event">
          <div className="ke95-toolbar">
            <div className="ke95-toolbar">
              <StatusBadge tone={item.level ?? "neutral"}>{item.scope ?? "issue"}</StatusBadge>
              <Mono>{item.title}</Mono>
            </div>
            {item.at_ms ? <Mono>{formatTime(item.at_ms)}</Mono> : null}
          </div>
          <Mono as="div">{item.detail}</Mono>
        </Inset>
      ))}
    </Stack>
  );
}

function Diagnostics({ ctx, data }) {
  const [viewState, setViewState] = useState({ snapshot: data, receivedAtMs: Date.now() });
  const snapshot = viewState.snapshot;
  const snapshotAt = formatSnapshotTime(viewState.receivedAtMs);
  const domains = useMemo(() => decorateDomains(snapshot.domains), [snapshot.domains]);
  const slaves = useMemo(() => decorateSlaves(snapshot.slaves), [snapshot.slaves]);
  const busIssues = useMemo(() => busCurrentIssues(snapshot.bus, snapshot.slice_ms), [snapshot.bus, snapshot.slice_ms]);
  const currentIssues = useMemo(
    () =>
      sortIssues([
        ...masterCurrentIssues(snapshot),
        ...dcCurrentIssues(snapshot.dc),
        ...busIssues,
        ...domains.flatMap((domain) => (domain.current_issue ? [domain.current_issue] : [])),
        ...slaves.flatMap((slave) => (slave.current_issue ? [slave.current_issue] : [])),
      ]),
    [snapshot, busIssues, domains, slaves]
  );
  const degradedDomains = domains.filter((domain) => domain.current_issue);
  const degradedSlaves = slaves.filter((slave) => slave.current_issue);
  const downLinks = snapshot.bus.links.filter((link) => link.status === "down").length;

  useEffect(() => {
    ctx.handleEvent("snapshot", (next) => {
      startTransition(() => {
        setViewState({ snapshot: next, receivedAtMs: Date.now() });
      });
    });
  }, [ctx]);

  return (
    <ModalShell
      title="Task Manager"
      subtitle={snapshot.last_failure ? `live master overview • last failure ${snapshot.last_failure}` : "live master overview"}
      status={
        <div className="ke95-diagnostics__status-strip">
          <StatusBadge tone={badgeTone(STATE_TONES, snapshot.state)}>{snapshot.state}</StatusBadge>
          <StatusBadge tone={badgeTone(LOCK_TONES, snapshot.dc?.lock_state ?? "disabled")}>
            {snapshot.dc?.lock_state ?? "disabled"}
          </StatusBadge>
          <StatusBadge tone={badgeTone(DC_RUNTIME_TONES, snapshot.dc?.runtime_state ?? "healthy")}>
            DC {snapshot.dc?.runtime_state ?? "healthy"}
          </StatusBadge>
          <StatusBadge tone="neutral">snapshot {snapshotAt}</StatusBadge>
        </div>
      }
    >
      {({ layoutVersion }) => (
        <LayoutVersionContext.Provider value={layoutVersion}>
          <Stack className="ke95-diagnostics">
            <SummaryGrid
              items={[
                { label: "State", value: snapshot.state },
                { label: "Target", value: snapshot.master.runtime_target ?? "n/a" },
                { label: "Current issues", value: formatCount(currentIssues.length) },
                { label: "Domains needing attention", value: formatCount(degradedDomains.length) },
                { label: "Slaves needing attention", value: formatCount(degradedSlaves.length) },
                { label: "Links down", value: formatCount(downLinks) },
                { label: "Snapshot", value: snapshotAt },
                { label: "Events tracked", value: formatCount(snapshot.timeline.length) },
                { label: "Window", value: sliceWindowLabel(snapshot.slice_ms) },
              ]}
            />

            <Tabs defaultActiveTab="Overview">
              <Tab title="Overview">
                <OverviewSection
                  snapshot={snapshot}
                  snapshotAt={snapshotAt}
                  currentIssues={currentIssues}
                  domains={domains}
                  slaves={slaves}
                />
              </Tab>
              <Tab title="Runtime">
                <RuntimeSection master={snapshot.master} dc={snapshot.dc} lastFailure={snapshot.last_failure} />
              </Tab>
              <Tab title="Domains">
                <DomainsSection domains={domains} />
              </Tab>
              <Tab title="Slaves">
                <SlavesSection slaves={slaves} />
              </Tab>
              <Tab title="Bus">
                <BusSection bus={snapshot.bus} />
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

function OverviewSection({ snapshot, snapshotAt, currentIssues, domains, slaves }) {
  const latestEvents = snapshot.timeline.slice(0, 6);
  const domainFocus = domains.slice(0, 6);
  const slaveFocus = slaves.slice(0, 8);
  const downLinks = snapshot.bus.links.filter((link) => link.status === "down").length;
  const droppedNow = latestSliceValue(snapshot.bus.frames.dropped_slices);
  const expiredNow = latestSliceValue(snapshot.bus.frames.expired_slices);
  const exceptionsNow = latestSliceValue(snapshot.bus.frames.exception_slices);
  const syncLabel =
    snapshot.dc?.configured && snapshot.dc?.active ? formatNs(snapshot.dc?.max_sync_diff_ns) : "inactive";

  return (
    <Stack>
      <Panel title="Current picture">
        <Stack compact>
          <SectionCopy>
            Start here. This tab is the live operator view: what state the master is in now, what currently needs attention, and where the pressure is coming from.
          </SectionCopy>
          <div className="ke95-toolbar ke95-diagnostics__status-strip">
            <StatusBadge tone={badgeTone(STATE_TONES, snapshot.state)}>{snapshot.state}</StatusBadge>
            <StatusBadge tone={badgeTone(LOCK_TONES, snapshot.dc?.lock_state ?? "disabled")}>
              DC {snapshot.dc?.lock_state ?? "disabled"}
            </StatusBadge>
            <StatusBadge tone={badgeTone(DC_RUNTIME_TONES, snapshot.dc?.runtime_state ?? "healthy")}>
              runtime {snapshot.dc?.runtime_state ?? "healthy"}
            </StatusBadge>
            <StatusBadge tone="neutral">snapshot {snapshotAt}</StatusBadge>
          </div>
          <SummaryGrid
            items={[
              { label: "Master", value: snapshot.state },
              { label: "Target", value: snapshot.master.runtime_target ?? "n/a" },
              { label: "Bus stable", value: snapshot.master.startup_slave_count != null ? `${snapshot.master.startup_slave_count} slaves` : "n/a" },
              { label: "Configuration", value: formatResult(snapshot.master.configuration_result) },
              { label: "Activation", value: formatResult(snapshot.master.activation_result) },
              { label: "Current issues", value: formatCount(currentIssues.length) },
              { label: "Links down", value: formatCount(downLinks) },
              { label: "Last failure", value: snapshot.last_failure ?? "none" },
            ]}
          />
          <PropertyList
            minWidth="12rem"
            items={[
              { label: "Realtime latency", value: `${formatUs(snapshot.bus.transactions.realtime.avg_latency_us)} avg • ${formatUs(snapshot.bus.transactions.realtime.last_latency_us)} last` },
              { label: "Reliable latency", value: `${formatUs(snapshot.bus.transactions.reliable.avg_latency_us)} avg • ${formatUs(snapshot.bus.transactions.reliable.last_latency_us)} last` },
              { label: "Realtime queue", value: `${formatCount(snapshot.bus.queues.realtime.peak_depth)} peak • ${formatCount(snapshot.bus.queues.realtime.last_depth)} last` },
              { label: "Sync diff", value: syncLabel },
              { label: "Dropped burst", value: `${formatCount(droppedNow)} latest • ${formatCount(snapshot.bus.frames.dropped)} total` },
              { label: "Expired RT burst", value: `${formatCount(expiredNow)} latest • ${formatCount(snapshot.bus.expired_realtime)} total` },
              { label: "Exceptions burst", value: `${formatCount(exceptionsNow)} latest • ${formatCount(snapshot.bus.exceptions)} total` },
              {
                label: "Traffic totals",
                value: `${formatBytes(snapshot.bus.frames.sent_bytes)} outbound • ${formatBytes(snapshot.bus.frames.received_bytes)} inbound`,
              },
            ]}
          />
        </Stack>
      </Panel>

      <Panel title="Needs attention now">
        {currentIssues.length ? (
          <IssueList items={currentIssues.slice(0, 12)} className="ke95-diagnostics__stable-feed" />
        ) : (
          <Inset className="ke95-diagnostics__event ke95-diagnostics__stable-feed">
            <Mono>The master currently looks clean: no active bus, runtime, domain, or slave issues are being reported.</Mono>
          </Inset>
        )}
      </Panel>

      <Panel title="Domain focus">
        <Stack compact>
          <SectionCopy>Worst domains first. Use the Domains tab for the full timing and fault history.</SectionCopy>
          <SummaryGrid items={domainSummaryItems(domains)} />
          {domainFocus.length ? (
            <div className="ke95-diagnostics__stable-table">
              <DataTable headers={["Domain", "State", "Health", "Cycle", "WKC", "Current issue"]}>
                {domainFocus.map((domain) => (
                  <tr key={domain.id}>
                    <td><Mono>{domain.id}</Mono></td>
                    <td><StatusBadge tone={badgeTone(DOMAIN_TONES, domain.state)}>{domain.state}</StatusBadge></td>
                    <td><StatusBadge tone={healthTone(domain.cycle_health)}>{formatCycleHealth(domain.cycle_health)}</StatusBadge></td>
                    <td><Mono>{formatUs(domain.last_cycle_us)}</Mono></td>
                    <td><Mono>{formatWkcContext(domain)}</Mono></td>
                    <td>
                      <div className="ke95-diagnostics__table-event">
                        <Mono>{domain.current_issue?.title ?? "healthy"}</Mono>
                        <Mono>{domain.current_issue?.detail ?? "healthy"}</Mono>
                      </div>
                    </td>
                  </tr>
                ))}
              </DataTable>
            </div>
          ) : (
            <Inset className="ke95-diagnostics__event ke95-diagnostics__stable-table">
              <Mono>No domains are running yet.</Mono>
            </Inset>
          )}
        </Stack>
      </Panel>

      <Panel title="Slave focus">
        <Stack compact>
          <SectionCopy>Worst slaves first. This view stays stable even when everything is healthy.</SectionCopy>
          <SummaryGrid items={slaveSummaryItems(slaves)} />
          {slaveFocus.length ? (
            <div className="ke95-diagnostics__stable-table">
              <DataTable headers={["Slave", "Station", "State", "Current issue", "Fault", "AL"]}>
                {slaveFocus.map((slave) => (
                  <tr key={slave.name}>
                    <td><Mono>{slave.name}</Mono></td>
                    <td><Mono>{slave.station != null ? formatHex(slave.station) : "n/a"}</Mono></td>
                    <td><StatusBadge tone={badgeTone(SLAVE_TONES, slave.al_state)}>{slave.al_state}</StatusBadge></td>
                    <td>
                      <div className="ke95-diagnostics__table-event">
                        <Mono>{slave.current_issue?.title ?? "healthy"}</Mono>
                        <Mono>{slave.current_issue?.detail ?? "healthy"}</Mono>
                      </div>
                    </td>
                    <td><Mono>{slave.fault ?? "none"}</Mono></td>
                    <td><Mono>{slave.al_error != null ? formatHex(slave.al_error) : "n/a"}</Mono></td>
                  </tr>
                ))}
              </DataTable>
            </div>
          ) : (
            <Inset className="ke95-diagnostics__event ke95-diagnostics__stable-table">
              <Mono>No slaves are running yet.</Mono>
            </Inset>
          )}
        </Stack>
      </Panel>

      <Panel title="Latest events">
        <EventFeed items={latestEvents} compact emptyLabel="No fault or recovery events yet" />
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
      <FrameSection frames={bus.frames} links={bus.links} expiredRealtime={bus.expired_realtime} exceptions={bus.exceptions} />
    </Stack>
  );
}

function RuntimeSection({ master, dc, lastFailure }) {
  return (
    <Stack>
      <MasterSection master={master} lastFailure={lastFailure} />
      <DcSection dc={dc} />
    </Stack>
  );
}

function TransactionCard({ title, accent, transaction, queue }) {
  return (
    <Panel title={title}>
      <Stack compact>
        <Mono as="div">
          latency last {formatUs(transaction.last_latency_us)} • avg {formatUs(transaction.avg_latency_us)} • status {transaction.last_status ?? "n/a"}
        </Mono>
        <Columns minWidth="22rem">
          <ChartPanel
            title="Latency"
            subtitle={`dispatches ${formatCount(transaction.dispatches)} • wkc ${formatCount(transaction.last_wkc)} • link ${transaction.last_link ?? "n/a"}`}
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
            { label: "Submissions", value: formatCount(transaction.count) },
            { label: "Transactions", value: formatCount(transaction.transactions) },
            { label: "Datagrams", value: formatCount(transaction.datagrams) },
            { label: "Queue peak", value: formatCount(queue.peak_depth) },
          ]}
        />
      </Stack>
    </Panel>
  );
}

function FrameSection({ frames, links, expiredRealtime, exceptions }) {
  return (
    <Stack>
      <Panel title="Bus frames">
        <Stack compact>
          <SectionCopy>
            Sent and received are independent traffic totals across the active bus links and ports. Redundant links can observe multiple arrivals for one exchange. Dropped counts local frame drops such as decode, index, or passthrough-copy rejection.
          </SectionCopy>
          <Mono as="div">RTT last {formatNs(frames.last_rtt_ns)} • peak {formatNs(frames.peak_rtt_ns)}</Mono>
          <Columns minWidth="22rem">
            <ChartPanel
              title="Traffic"
              subtitle={`outbound ${formatCount(frames.sent)} • inbound ${formatCount(frames.received)} • local drops ${formatCount(frames.dropped)}`}
              series={[
                { label: "Sent", slices: frames.sent_slices, stroke: "#0f766e", fill: "#0f766e20" },
                { label: "Received", slices: frames.received_slices, stroke: "#2563eb", fill: "#2563eb20" },
                { label: "Dropped", slices: frames.dropped_slices, stroke: "#be123c", fill: "#be123c20" },
              ]}
              emptyLabel="No frame traffic yet"
            />
            <ChartPanel
              title="Payload throughput"
              subtitle={`outbound ${formatBytes(frames.sent_bytes)} • inbound ${formatBytes(frames.received_bytes)} • local drops ${formatBytes(frames.dropped_bytes)}`}
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
              subtitle={`links ${formatCount(links.length)} • exceptions ${formatCount(exceptions)}`}
              series={[{ label: "RTT", slices: frames.rtt_slices, stroke: "#7c3aed", fill: "#7c3aed20" }]}
              yUnit="ns"
              emptyLabel="No RTT samples yet"
            />
            <ChartPanel
              title="Anomalies"
              subtitle={`expired realtime ${formatCount(expiredRealtime)} • dropped ${formatCount(frames.dropped)}`}
              series={[
                { label: "Expired", slices: frames.expired_slices, stroke: "#ea580c", fill: "#ea580c20" },
                { label: "Exceptions", slices: frames.exception_slices, stroke: "#dc2626", fill: "#dc262620" },
                { label: "Dropped", slices: frames.dropped_slices, stroke: "#7f1d1d", fill: "#7f1d1d20" },
              ]}
              emptyLabel="No bus faults recorded"
            />
          </Columns>
          <SummaryGrid
            items={[
              { label: "Outbound payload", value: formatBytes(frames.sent_bytes) },
              { label: "Inbound payload", value: formatBytes(frames.received_bytes) },
              { label: "Local drop payload", value: formatBytes(frames.dropped_bytes) },
              { label: "Local drop count", value: formatCount(frames.dropped) },
              { label: "Expired RT", value: formatCount(expiredRealtime) },
              { label: "Exceptions", value: formatCount(exceptions) },
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
                <PropertyList
                  minWidth="12rem"
                  items={[
                    { label: "Endpoint", value: link.endpoint ?? "n/a" },
                    { label: "Outbound", value: formatCount(link.sent) },
                    { label: "Inbound", value: formatCount(link.received) },
                    { label: "Local drops", value: formatCount(link.dropped) },
                    { label: "Last update", value: formatLinkTime(link.at_ms) },
                    { label: "Reason", value: link.reason ?? "n/a" },
                  ]}
                />
                {link.ports?.length ? (
                  <div className="ke95-diagnostics__port-grid">
                    {link.ports.map((port) => (
                      <Inset key={port.port} className="ke95-diagnostics__port-card">
                        <Mono as="div">{port.port}</Mono>
                        <Mono as="div">out {formatCount(port.sent)} • in {formatCount(port.received)}</Mono>
                        <Mono as="div">
                          {formatBytes(port.sent_bytes)} • {formatBytes(port.received_bytes)}
                        </Mono>
                      </Inset>
                    ))}
                  </div>
                ) : null}
              </Inset>
            ))}
          </Stack>
        )}
      </Panel>
    </Stack>
  );
}

function MasterSection({ master, lastFailure }) {
  const stateEvents = master.state_changes.map((change) => ({
    id: `${change.at_ms}-${change.from}-${change.to}`,
    at_ms: change.at_ms,
    level: masterStateEventLevel(change.to),
    title: masterStateChangeTitle(change),
    detail: masterStateChangeDetail(change),
  }));

  const decisionEvents = master.dc_lock_decisions.map((decision) => ({
    id: `${decision.at_ms}-${decision.transition}-${decision.outcome}`,
    at_ms: decision.at_ms,
    level: decision.transition === "lost" ? "warn" : "info",
    title: `DC lock ${decision.transition}`,
    detail: `${decision.outcome} • policy ${decision.policy} • lock ${decision.lock_state}${decision.max_sync_diff_ns != null ? ` • ${formatNs(decision.max_sync_diff_ns)}` : ""}`,
  }));

  return (
    <Panel title="Master lifecycle">
      <Stack compact>
        <SectionCopy>
          This is the control-plane view: what state the master wants, what happened during configuration and activation, and whether DC policy decisions changed that path.
        </SectionCopy>
        <div className="ke95-toolbar">
          <StatusBadge tone={badgeTone(STATE_TONES, master.public_state)}>{master.public_state}</StatusBadge>
          <StatusBadge tone={badgeTone(RESULT_TONES, master.configuration_result?.status ?? "unknown")}>
            config {master.configuration_result?.status ?? "n/a"}
          </StatusBadge>
          <StatusBadge tone={badgeTone(RESULT_TONES, master.activation_result?.status ?? "unknown")}>
            activation {master.activation_result?.status ?? "n/a"}
          </StatusBadge>
        </div>
        <Columns minWidth="18rem">
          <PropertyList
            minWidth="12rem"
            items={[
              { label: "Public state", value: master.public_state },
              { label: "Target", value: master.runtime_target ?? "n/a" },
              { label: "Bus stable", value: master.startup_slave_count != null ? `${master.startup_slave_count} slave(s)` : "n/a" },
              { label: "Last failure", value: lastFailure ?? "none" },
            ]}
          />
          <PropertyList
            minWidth="12rem"
            items={[
              { label: "Config result", value: formatResult(master.configuration_result) },
              { label: "Config duration", value: formatMs(master.configuration_result?.duration_ms) },
              { label: "Activation result", value: formatResult(master.activation_result) },
              { label: "Activation duration", value: formatMs(master.activation_result?.duration_ms) },
              { label: "Blocked slaves", value: formatCount(master.activation_result?.blocked_count) },
            ]}
          />
        </Columns>
        <Columns minWidth="22rem">
          <Panel title="State changes">
            <EventFeed items={stateEvents.slice(0, 8)} emptyLabel="No master state changes yet" />
          </Panel>
          <Panel title="DC lock decisions">
            <EventFeed items={decisionEvents.slice(0, 8)} emptyLabel="No master DC lock decisions yet" />
          </Panel>
        </Columns>
      </Stack>
    </Panel>
  );
}

function DcSection({ dc }) {
  const lockEvents = dc.lock_events.map((event, index) => ({
    id: `${event.at_ms ?? index}-${event.from}-${event.to}`,
    at_ms: event.at_ms,
    level: event.to === "locked" ? "info" : "warn",
    title: `${event.from} -> ${event.to}`,
    detail: event.max_sync_diff_ns != null ? formatNs(event.max_sync_diff_ns) : "sync diff unavailable",
  }));

  const runtimeEvents = dc.runtime_events.map((event, index) => ({
    id: `${event.at_ms ?? index}-${event.from}-${event.to}`,
    at_ms: event.at_ms,
    level: event.to === "healthy" ? "info" : "warn",
    title: `${event.from} -> ${event.to}`,
    detail: [event.reason, `failures ${event.consecutive_failures}`].filter(Boolean).join(" • "),
  }));

  return (
    <Panel title="Distributed clocks">
      <Stack compact>
        <SectionCopy>
          Watch DC lock and runtime health together. Lock state explains synchronization; runtime state tells you whether the master considers that synchronization healthy enough to keep running cleanly.
        </SectionCopy>
        <div className="ke95-toolbar">
          <StatusBadge tone={badgeTone(LOCK_TONES, dc.lock_state)}>{dc.lock_state}</StatusBadge>
          <StatusBadge tone={badgeTone(DC_RUNTIME_TONES, dc.runtime_state)}>{dc.runtime_state}</StatusBadge>
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
              { label: "Configured", value: formatBoolean(dc.configured) },
              { label: "Active", value: formatBoolean(dc.active) },
              { label: "Cycle", value: formatNs(dc.cycle_ns) },
              { label: "Reference clock", value: dc.reference_clock ?? "n/a" },
              { label: "Reference station", value: dc.reference_station != null ? formatHex(dc.reference_station) : "n/a" },
              { label: "Await lock", value: formatBoolean(dc.await_lock) },
              { label: "Lock policy", value: dc.lock_policy ?? "n/a" },
              { label: "Monitor failures", value: formatCount(dc.monitor_failures) },
              { label: "Runtime reason", value: dc.runtime_reason ?? "n/a" },
              { label: "Consecutive failures", value: formatCount(dc.consecutive_failures) },
            ]}
          />
        </Columns>
        <Columns minWidth="22rem">
          <Panel title="Lock changes">
            <EventFeed items={lockEvents.slice(0, 8)} emptyLabel="No DC lock changes yet" />
          </Panel>
          <Panel title="Runtime changes">
            <EventFeed items={runtimeEvents.slice(0, 8)} emptyLabel="No DC runtime changes yet" />
          </Panel>
        </Columns>
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
          <SectionCopy>
            This is the cyclic exchange view. Read the table first for current domain health, then drill into the per-domain charts when you need timing and failure context.
          </SectionCopy>
          <SummaryGrid items={domainSummaryItems(domains)} />
          <DataTable headers={["Domain", "State", "Health", "Cycle", "WKC", "Current issue"]}>
            {domains.map((domain) => (
              <tr key={`${domain.id}-summary`}>
                <td><Mono>{domain.id}</Mono></td>
                <td><StatusBadge tone={badgeTone(DOMAIN_TONES, domain.state)}>{domain.state}</StatusBadge></td>
                <td><StatusBadge tone={healthTone(domain.cycle_health)}>{formatCycleHealth(domain.cycle_health)}</StatusBadge></td>
                <td><Mono>{formatUs(domain.last_cycle_us)}</Mono></td>
                <td><Mono>{formatWkcContext(domain)}</Mono></td>
                <td>
                  <div className="ke95-diagnostics__table-event">
                    <Mono>{domain.current_issue?.title ?? "healthy"}</Mono>
                    <Mono>{domain.current_issue?.detail ?? "healthy"}</Mono>
                  </div>
                </td>
              </tr>
            ))}
          </DataTable>
          {domains.map((domain) => (
            <Inset key={domain.id} className="ke95-diagnostics__domain">
              <div className="ke95-toolbar">
                <Mono>{domain.id}</Mono>
                <div className="ke95-toolbar">
                  <StatusBadge tone={badgeTone(DOMAIN_TONES, domain.state)}>{domain.state}</StatusBadge>
                  <StatusBadge tone={healthTone(domain.cycle_health)}>{formatCycleHealth(domain.cycle_health)}</StatusBadge>
                </div>
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
                  title="Invalid cycles"
                  subtitle={`invalid ${formatCount(domain.invalid_events)} • transport misses ${formatCount(domain.transport_miss_events)}`}
                  series={[
                    { label: "Invalid", slices: domain.invalid_slices, stroke: "#dc2626", fill: "#dc262620" },
                    { label: "Transport miss", slices: domain.transport_miss_slices, stroke: "#7f1d1d", fill: "#7f1d1d20" },
                  ]}
                  emptyLabel="No invalid cycles recorded"
                />
              </Columns>
              <PropertyList
                minWidth="12rem"
                items={[
                  { label: "Configured cycle", value: formatUs(domain.cycle_time_us) },
                  { label: "Expected WKC", value: formatWkcContext(domain) },
                  { label: "Logical base", value: domain.logical_base != null ? formatHex(domain.logical_base, 6) : "n/a" },
                  { label: "Image size", value: domain.image_size != null ? `${domain.image_size} B` : "n/a" },
                  { label: "Cycle count", value: formatCount(domain.cycle_count) },
                  { label: "Snapshot invalid reason", value: domain.last_invalid_reason ?? "n/a" },
                ]}
              />
              {(domain.last_invalid || domain.last_transport_miss || domain.stop_reason || domain.crash_reason) ? (
                <Stack compact>
                  {domain.last_invalid ? (
                    <Inset className="ke95-diagnostics__event">
                      <Mono>invalid • {domain.last_invalid.reason ?? "unknown"} • WKC {domain.last_invalid.actual_wkc ?? "?"}/{domain.last_invalid.expected_wkc ?? "?"}</Mono>
                    </Inset>
                  ) : null}
                  {domain.last_transport_miss ? (
                    <Inset className="ke95-diagnostics__event">
                      <Mono>
                        transport miss • {domain.last_transport_miss.reason ?? "unknown"} • misses {domain.last_transport_miss.consecutive_miss_count ?? "?"}
                      </Mono>
                    </Inset>
                  ) : null}
                  {domain.stop_reason ? (
                    <Inset className="ke95-diagnostics__event">
                      <Mono>stopped • {domain.stop_reason}</Mono>
                    </Inset>
                  ) : null}
                  {domain.crash_reason ? (
                    <Inset className="ke95-diagnostics__event">
                      <Mono>crashed • {domain.crash_reason}</Mono>
                    </Inset>
                  ) : null}
                </Stack>
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
          <SectionCopy>
            This table is sorted with problem slaves first. Focus on state, active fault markers, AL error codes, and the most recent slave-local event.
          </SectionCopy>
          <SummaryGrid items={slaveSummaryItems(slaves)} />
          <DataTable headers={["Name", "Station", "State", "Current issue", "Fault", "AL", "Last event"]}>
            {slaves.map((slave) => (
              <tr key={slave.name}>
                <td><Mono>{slave.name}</Mono></td>
                <td><Mono>{slave.station != null ? formatHex(slave.station) : "n/a"}</Mono></td>
                <td><StatusBadge tone={badgeTone(SLAVE_TONES, slave.al_state)}>{slave.al_state}</StatusBadge></td>
                <td>
                  <div className="ke95-diagnostics__table-event">
                    <Mono>{slave.current_issue?.title ?? "healthy"}</Mono>
                    <Mono>{slave.current_issue?.detail ?? "healthy"}</Mono>
                  </div>
                </td>
                <td><Mono>{slave.fault ?? "none"}</Mono></td>
                <td><Mono>{slave.al_error != null ? formatHex(slave.al_error) : "n/a"}</Mono></td>
                <td>
                  {slave.last_event ? (
                    <div className="ke95-diagnostics__table-event">
                      <Mono>{`${slave.last_event.title} • ${formatTime(slave.last_event.at_ms)}`}</Mono>
                      <Mono>{slave.last_event.detail}</Mono>
                    </div>
                  ) : (
                    <Mono>n/a</Mono>
                  )}
                </td>
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
          <SectionCopy>
            This is the chronological story. Keep this tab open when you want to correlate master transitions, domain degradation, link changes, and slave events.
          </SectionCopy>
          <EventFeed items={timeline} emptyLabel="No fault or recovery events yet" />
        </Stack>
      )}
    </Panel>
  );
}
