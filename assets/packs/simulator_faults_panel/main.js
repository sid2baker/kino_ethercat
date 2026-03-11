import "./main.css";

import React, { startTransition, useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";

import {
  Button,
  Columns,
  ControlField,
  DataTable,
  Dropdown,
  EmptyState,
  InlineButtons,
  Input,
  MessageLine,
  Mono,
  Panel,
  PropertyList,
  Shell,
  Stack,
  StatusBadge,
  SummaryGrid,
} from "../../ui/react95";

const UDP_MODES = [
  { value: "truncate", label: "Truncate reply" },
  { value: "unsupported_type", label: "Unsupported reply type" },
  { value: "wrong_idx", label: "Wrong datagram index" },
  { value: "replay_previous", label: "Replay previous reply" },
];

const RUNTIME_QUEUE_KINDS = [
  { value: "drop_responses", label: "Drop responses" },
  { value: "wkc_offset", label: "WKC offset" },
  { value: "disconnect", label: "Disconnect slave" },
];

export async function init(ctx, data) {
  await ctx.importCSS("main.css");
  const root = createRoot(ctx.root);
  root.render(<SimulatorFaultsPanel ctx={ctx} data={data} />);
}

function statusTone(status) {
  return status === "running" ? "ok" : status === "offline" ? "neutral" : "warn";
}

function FaultTable({ labels, emptyText }) {
  if (!labels?.length) {
    return <EmptyState>{emptyText}</EmptyState>;
  }

  return (
    <DataTable headers={["#", "Fault"]}>
      {labels.map((label, index) => (
        <tr key={`${label}-${index}`}>
          <td>
            <Mono>{index + 1}</Mono>
          </td>
          <td>
            <Mono>{label}</Mono>
          </td>
        </tr>
      ))}
    </DataTable>
  );
}

function SimulatorFaultsPanel({ ctx, data }) {
  const [snapshot, setSnapshot] = useState(data);
  const [selectedSlave, setSelectedSlave] = useState(data.slave_options?.[0] ?? "");
  const [wkcOffset, setWkcOffset] = useState(String(data.runtime_faults?.wkc_offset ?? 0));
  const [alErrorCode, setAlErrorCode] = useState("0x001B");
  const [mailboxIndex, setMailboxIndex] = useState("0x1600");
  const [mailboxSubindex, setMailboxSubindex] = useState("0x00");
  const [mailboxAbortCode, setMailboxAbortCode] = useState("0x06010002");
  const [runtimeQueueKind, setRuntimeQueueKind] = useState("drop_responses");
  const [runtimeQueuePlan, setRuntimeQueuePlan] = useState("next");
  const [runtimeQueueCount, setRuntimeQueueCount] = useState("3");
  const [runtimeQueueValue, setRuntimeQueueValue] = useState("0");
  const [udpFaultMode, setUdpFaultMode] = useState("truncate");
  const [udpFaultPlan, setUdpFaultPlan] = useState("next");
  const [udpFaultCount, setUdpFaultCount] = useState("3");

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
    setWkcOffset(String(snapshot.runtime_faults?.wkc_offset ?? 0));
  }, [snapshot.runtime_faults?.wkc_offset]);

  const disabled = snapshot.status !== "running";
  const udpDisabled = disabled || !snapshot.udp_faults?.enabled;
  const runtimeFaults = snapshot.runtime_faults ?? {};
  const udpFaults = snapshot.udp_faults ?? {};
  const disconnected = runtimeFaults.disconnected ?? [];
  const runtimeStickySummary = runtimeFaults.sticky_labels?.length
    ? runtimeFaults.sticky_labels.join(" | ")
    : "none";
  const status = <StatusBadge tone={statusTone(snapshot.status)}>{snapshot.status}</StatusBadge>;

  return (
    <Shell title="Simulator faults" subtitle={snapshot.kind} status={status}>
      <Stack className="ke95-simulator-faults-panel">
        <MessageLine tone={snapshot.message?.level === "error" ? "error" : "info"}>
          {snapshot.message?.text ?? null}
        </MessageLine>

        <SummaryGrid items={snapshot.summary ?? []} />

        <Panel
          title="Runtime faults"
          actions={
            <InlineButtons>
              <Button
                disabled={disabled}
                onClick={() => ctx.pushEvent("action", { id: "inject_drop_responses" })}
              >
                Drop responses
              </Button>
              <Button
                disabled={disabled || runtimeFaults.active_count === 0}
                onClick={() => ctx.pushEvent("action", { id: "clear_runtime_faults" })}
              >
                Clear runtime
              </Button>
              <Button
                disabled={disabled || (runtimeFaults.active_count === 0 && udpFaults.active_count === 0)}
                onClick={() => ctx.pushEvent("action", { id: "clear_faults" })}
              >
                Clear all
              </Button>
            </InlineButtons>
          }
        >
          <Stack compact>
            <PropertyList
              items={[
                { label: "Sticky faults", value: runtimeStickySummary },
                { label: "Next exchange", value: runtimeFaults.next_label ?? "none" },
                { label: "Queued exchanges", value: String(runtimeFaults.pending_count ?? 0) },
                { label: "Disconnected", value: disconnected.length ? disconnected.join(", ") : "none" },
              ]}
            />

            <Columns minWidth="14rem">
              <ControlField label="WKC offset">
                <Input value={wkcOffset} onChange={(event) => setWkcOffset(event.target.value)} />
              </ControlField>
              <InlineButtons className="ke95-simulator-faults-panel__row-actions">
                <Button
                  disabled={disabled}
                  onClick={() => ctx.pushEvent("action", { id: "set_wkc_offset", value: wkcOffset })}
                >
                  Apply WKC offset
                </Button>
              </InlineButtons>
            </Columns>

            <Columns minWidth="12rem">
              <ControlField label="Queue fault">
                <Dropdown value={runtimeQueueKind} onChange={(event) => setRuntimeQueueKind(event.target.value)}>
                  {RUNTIME_QUEUE_KINDS.map((option) => (
                    <option key={option.value} value={option.value}>
                      {option.label}
                    </option>
                  ))}
                </Dropdown>
              </ControlField>
              <ControlField label="Plan">
                <Dropdown value={runtimeQueuePlan} onChange={(event) => setRuntimeQueuePlan(event.target.value)}>
                  <option value="next">Next exchange</option>
                  <option value="count">Next N exchanges</option>
                </Dropdown>
              </ControlField>
              {runtimeQueuePlan === "count" ? (
                <ControlField label="Count">
                  <Input value={runtimeQueueCount} onChange={(event) => setRuntimeQueueCount(event.target.value)} />
                </ControlField>
              ) : null}
              {runtimeQueueKind === "wkc_offset" ? (
                <ControlField label="Offset">
                  <Input value={runtimeQueueValue} onChange={(event) => setRuntimeQueueValue(event.target.value)} />
                </ControlField>
              ) : null}
              {runtimeQueueKind === "disconnect" ? (
                <ControlField label="Slave">
                  <Dropdown value={selectedSlave} onChange={(event) => setSelectedSlave(event.target.value)}>
                    {(snapshot.slave_options ?? []).map((name) => (
                      <option key={name} value={name}>
                        {name}
                      </option>
                    ))}
                  </Dropdown>
                </ControlField>
              ) : null}
              <InlineButtons className="ke95-simulator-faults-panel__row-actions">
                <Button
                  disabled={disabled}
                  onClick={() =>
                    ctx.pushEvent("action", {
                      id: "queue_runtime_fault",
                      kind: runtimeQueueKind,
                      plan: runtimeQueuePlan,
                      count: runtimeQueueCount,
                      value: runtimeQueueValue,
                      slave: selectedSlave,
                    })
                  }
                >
                  Queue runtime fault
                </Button>
              </InlineButtons>
            </Columns>

            <FaultTable
              labels={runtimeFaults.pending_labels}
              emptyText="No runtime exchange faults are queued."
            />
          </Stack>
        </Panel>

        <Panel
          title="UDP reply faults"
          actions={
            <InlineButtons>
              <Button
                disabled={udpDisabled || udpFaults.active_count === 0}
                onClick={() => ctx.pushEvent("action", { id: "clear_udp_faults" })}
              >
                Clear UDP faults
              </Button>
            </InlineButtons>
          }
        >
          <Stack compact>
            <PropertyList
              items={[
                { label: "Endpoint", value: udpFaults.endpoint ?? "disabled" },
                { label: "Next reply", value: udpFaults.next_label ?? "none" },
                { label: "Queued replies", value: String(udpFaults.active_count ?? 0) },
                {
                  label: "Last response captured",
                  value: udpFaults.last_response_captured ? "yes" : "no",
                },
              ]}
            />

            <Columns minWidth="12rem">
              <ControlField label="Reply fault">
                <Dropdown value={udpFaultMode} onChange={(event) => setUdpFaultMode(event.target.value)}>
                  {UDP_MODES.map((option) => (
                    <option key={option.value} value={option.value}>
                      {option.label}
                    </option>
                  ))}
                </Dropdown>
              </ControlField>
              <ControlField label="Plan">
                <Dropdown value={udpFaultPlan} onChange={(event) => setUdpFaultPlan(event.target.value)}>
                  <option value="next">Next reply</option>
                  <option value="count">Next N replies</option>
                </Dropdown>
              </ControlField>
              {udpFaultPlan === "count" ? (
                <ControlField label="Count">
                  <Input value={udpFaultCount} onChange={(event) => setUdpFaultCount(event.target.value)} />
                </ControlField>
              ) : null}
              <InlineButtons className="ke95-simulator-faults-panel__row-actions">
                <Button
                  disabled={udpDisabled}
                  onClick={() =>
                    ctx.pushEvent("action", {
                      id: "queue_udp_fault",
                      mode: udpFaultMode,
                      plan: udpFaultPlan,
                      count: udpFaultCount,
                    })
                  }
                >
                  Queue UDP fault
                </Button>
              </InlineButtons>
            </Columns>

            <FaultTable
              labels={udpFaults.pending_labels}
              emptyText="No UDP reply faults are queued."
            />
          </Stack>
        </Panel>

        <Panel title="Slave-local faults">
          <Stack compact>
            <Columns minWidth="12rem">
              <ControlField label="Slave">
                <Dropdown value={selectedSlave} onChange={(event) => setSelectedSlave(event.target.value)}>
                  {(snapshot.slave_options ?? []).map((name) => (
                    <option key={name} value={name}>
                      {name}
                    </option>
                  ))}
                </Dropdown>
              </ControlField>
              <InlineButtons className="ke95-simulator-faults-panel__row-actions">
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
              </InlineButtons>
            </Columns>

            <Columns minWidth="14rem">
              <ControlField label="AL error code">
                <Input value={alErrorCode} onChange={(event) => setAlErrorCode(event.target.value)} />
              </ControlField>
              <InlineButtons className="ke95-simulator-faults-panel__row-actions">
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
              </InlineButtons>
            </Columns>

            <Columns minWidth="10rem">
              <ControlField label="Mailbox index">
                <Input value={mailboxIndex} onChange={(event) => setMailboxIndex(event.target.value)} />
              </ControlField>
              <ControlField label="Subindex">
                <Input value={mailboxSubindex} onChange={(event) => setMailboxSubindex(event.target.value)} />
              </ControlField>
              <ControlField label="Abort code">
                <Input value={mailboxAbortCode} onChange={(event) => setMailboxAbortCode(event.target.value)} />
              </ControlField>
              <InlineButtons className="ke95-simulator-faults-panel__row-actions">
                <Button
                  disabled={disabled || !selectedSlave}
                  onClick={() =>
                    ctx.pushEvent("action", {
                      id: "inject_mailbox_abort",
                      slave: selectedSlave,
                      index: mailboxIndex,
                      subindex: mailboxSubindex,
                      abort_code: mailboxAbortCode,
                    })
                  }
                >
                  Mailbox abort
                </Button>
              </InlineButtons>
            </Columns>
          </Stack>
        </Panel>
      </Stack>
    </Shell>
  );
}
