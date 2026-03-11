import "./main.css";

import React, { startTransition, useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";

import {
  Button,
  ControlField,
  DataTable,
  Dropdown,
  EmptyState,
  Input,
  MessageLine,
  Mono,
  Panel,
  Shell,
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
  const [snapshot, setSnapshot] = useState(data);
  const [selectedSlave, setSelectedSlave] = useState(data.slave_options?.[0] ?? "");
  const [wkcOffset, setWkcOffset] = useState(String(data.faults?.wkc_offset ?? 0));
  const [alErrorCode, setAlErrorCode] = useState("0x001B");

  useEffect(() => {
    ctx.handleEvent("snapshot", (next) => {
      startTransition(() => setSnapshot(next));
    });
  }, [ctx]);

  const slaveOptionsKey = useMemo(
    () => (snapshot.slave_options ?? []).join("|"),
    [snapshot.slave_options]
  );

  useEffect(() => {
    const options = snapshot.slave_options ?? [];
    setSelectedSlave((current) => (options.includes(current) ? current : options[0] ?? ""));
  }, [slaveOptionsKey, snapshot.slave_options]);

  useEffect(() => {
    setWkcOffset(String(snapshot.faults?.wkc_offset ?? 0));
  }, [snapshot.faults?.wkc_offset]);

  const disabled = snapshot.status !== "running";
  const status = <StatusBadge tone={statusTone(snapshot.status)}>{snapshot.status}</StatusBadge>;
  const disconnected = snapshot.faults?.disconnected ?? [];

  return (
    <Shell title={snapshot.title} subtitle={snapshot.kind} status={status}>
      {({ fullscreenActive }) => (
        <div className={`ke95-simulator-panel${fullscreenActive ? " ke95-simulator-panel--fullscreen" : ""}`}>
          <MessageLine tone={snapshot.message?.level === "error" ? "error" : "info"}>
            {snapshot.message?.text ?? null}
          </MessageLine>

          <SummaryGrid items={snapshot.summary ?? []} />

          <Panel
            title="Fault injection"
            className="ke95-simulator-panel__faults"
            actions={
              <div className="ke95-simulator-panel__fault-actions">
                <Button
                  disabled={disabled}
                  onClick={() => ctx.pushEvent("action", { id: "inject_drop_responses" })}
                >
                  Drop responses
                </Button>
                <Button disabled={disabled} onClick={() => ctx.pushEvent("action", { id: "clear_faults" })}>
                  Clear faults
                </Button>
              </div>
            }
          >
            <div className="ke95-simulator-panel__fault-grid">
              <div className="ke95-toolbar">
                <ControlField label="WKC offset" className="ke95-fill">
                  <Input
                    className="ke95-fill"
                    value={wkcOffset}
                    onChange={(event) => setWkcOffset(event.target.value)}
                  />
                </ControlField>
                <Button
                  disabled={disabled}
                  onClick={() => ctx.pushEvent("action", { id: "set_wkc_offset", value: wkcOffset })}
                >
                  Apply
                </Button>
              </div>

              <div className="ke95-toolbar">
                <ControlField label="Slave" className="ke95-fill">
                  <Dropdown
                    value={selectedSlave}
                    className="ke95-fill"
                    onChange={(event) => setSelectedSlave(event.target.value)}
                  >
                    {(snapshot.slave_options ?? []).map((name) => (
                      <option key={name} value={name}>
                        {name}
                      </option>
                    ))}
                  </Dropdown>
                </ControlField>
                <Button
                  disabled={disabled || !selectedSlave}
                  onClick={() => ctx.pushEvent("action", { id: "inject_disconnect", slave: selectedSlave })}
                >
                  Disconnect
                </Button>
                <Button
                  disabled={disabled || !selectedSlave}
                  onClick={() => ctx.pushEvent("action", { id: "retreat_to_safeop", slave: selectedSlave })}
                >
                  SAFEOP
                </Button>
              </div>

              <div className="ke95-toolbar">
                <ControlField label="AL error code" className="ke95-fill">
                  <Input
                    className="ke95-fill"
                    value={alErrorCode}
                    onChange={(event) => setAlErrorCode(event.target.value)}
                  />
                </ControlField>
                <Button
                  disabled={disabled || !selectedSlave}
                  onClick={() =>
                    ctx.pushEvent("action", {
                      id: "inject_al_error",
                      slave: selectedSlave,
                      code: alErrorCode,
                    })
                  }
                >
                  Latch AL error
                </Button>
              </div>
            </div>

            <div className="ke95-simulator-panel__note">
              <Mono>
                Disconnected slaves: {disconnected.length ? disconnected.join(", ") : "none"}
              </Mono>
            </div>
          </Panel>

          <Panel title="Slaves" className="ke95-simulator-panel__table">
            <SlaveTable slaves={snapshot.slaves ?? []} />
          </Panel>

          <div className="ke95-simulator-panel__tables">
            <Panel title="Connections" className="ke95-simulator-panel__table">
              <ConnectionTable connections={snapshot.connections ?? []} />
            </Panel>

            <Panel title="Subscriptions" className="ke95-simulator-panel__table">
              <SubscriptionTable subscriptions={snapshot.subscriptions ?? []} />
            </Panel>
          </div>
        </div>
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
