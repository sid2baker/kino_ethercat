import "./main.css";

import React, { startTransition, useEffect } from "react";
import { createRoot } from "react-dom/client";

import {
  DataTable,
  EmptyState,
  MessageLine,
  Mono,
  Panel,
  PropertyList,
  Shell,
  Stack,
  StatusBadge,
  SummaryGrid,
} from "../../ui/react95";

export async function init(ctx, data) {
  await ctx.importCSS("main.css");
  const root = createRoot(ctx.root);
  root.render(<SimulatorPanel ctx={ctx} data={data} />);
}

function statusTone(status) {
  return status === "running" ? "ok" : status === "offline" ? "neutral" : "warn";
}

function stateTone(state) {
  const value = String(state ?? "").toLowerCase();

  if (value === "op") return "ok";
  if (value === "safeop" || value === "preop") return "warn";
  if (value === "init" || value === "bootstrap") return "neutral";
  return "neutral";
}

function SimulatorPanel({ ctx, data }) {
  const [snapshot, setSnapshot] = React.useState(data);
  const status = <StatusBadge tone={statusTone(snapshot.status)}>{snapshot.status}</StatusBadge>;

  useEffect(() => {
    ctx.handleEvent("snapshot", (next) => {
      startTransition(() => setSnapshot(next));
    });
  }, [ctx]);

  return (
    <Shell title={snapshot.title} subtitle={snapshot.kind} status={status}>
      {({ fullscreenActive }) => (
        <Stack className={`ke95-simulator-panel${fullscreenActive ? " ke95-simulator-panel--fullscreen" : ""}`}>
          <MessageLine tone={snapshot.message?.level === "error" ? "error" : "info"}>
            {snapshot.message?.text ?? null}
          </MessageLine>

          <SummaryGrid items={snapshot.summary ?? []} />

          <Panel title="Fault summary">
            <PropertyList items={snapshot.fault_summary ?? []} />
          </Panel>

          <Panel title="Slaves" className="ke95-simulator-panel__table">
            <SlaveTable slaves={snapshot.slaves ?? []} />
          </Panel>

          <Panel title="Connections" className="ke95-simulator-panel__table">
            <ConnectionTable connections={snapshot.connections ?? []} />
          </Panel>

          <Panel title="Subscriptions" className="ke95-simulator-panel__table">
            <SubscriptionTable subscriptions={snapshot.subscriptions ?? []} />
          </Panel>
        </Stack>
      )}
    </Shell>
  );
}

function SlaveTable({ slaves }) {
  if (!slaves.length) {
    return <EmptyState>No simulated devices are running.</EmptyState>;
  }

  return (
    <DataTable headers={["Name", "Profile", "State", "Station", "AL status", "Signals", "Values", "DC"]}>
      {slaves.map((slave) => (
        <tr key={slave.key}>
          <td>
            <Mono>{slave.name}</Mono>
          </td>
          <td>
            <Mono>{slave.profile}</Mono>
          </td>
          <td>
            <StatusBadge tone={stateTone(slave.state)}>{slave.state}</StatusBadge>
          </td>
          <td>
            <Mono>{slave.station}</Mono>
          </td>
          <td>
            <Mono>{`${slave.al_status_code} (${slave.al_error})`}</Mono>
          </td>
          <td>
            <Mono>{slave.signals}</Mono>
          </td>
          <td className="ke95-simulator-panel__values">
            <Mono>{slave.values}</Mono>
          </td>
          <td>
            <Mono>{slave.dc}</Mono>
          </td>
        </tr>
      ))}
    </DataTable>
  );
}

function ConnectionTable({ connections }) {
  if (!connections.length) {
    return <EmptyState>No signal wiring has been configured.</EmptyState>;
  }

  return (
    <DataTable headers={["Source", "Target"]}>
      {connections.map((connection) => (
        <tr key={connection.key}>
          <td>
            <Mono>{connection.source}</Mono>
          </td>
          <td>
            <Mono>{connection.target}</Mono>
          </td>
        </tr>
      ))}
    </DataTable>
  );
}

function SubscriptionTable({ subscriptions }) {
  if (!subscriptions.length) {
    return <EmptyState>No simulator signal subscriptions are active.</EmptyState>;
  }

  return (
    <DataTable headers={["Slave", "Signal", "PID"]}>
      {subscriptions.map((subscription) => (
        <tr key={subscription.key}>
          <td>
            <Mono>{subscription.slave}</Mono>
          </td>
          <td>
            <Mono>{subscription.signal}</Mono>
          </td>
          <td>
            <Mono>{subscription.pid}</Mono>
          </td>
        </tr>
      ))}
    </DataTable>
  );
}
