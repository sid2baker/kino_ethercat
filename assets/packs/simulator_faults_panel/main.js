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
  TextArea,
} from "../../ui/react95";

const RUNTIME_FAULTS = [
  { value: "drop_responses", label: "Drop responses" },
  { value: "wkc_offset", label: "WKC offset" },
  { value: "command_wkc_offset", label: "Command WKC offset" },
  { value: "logical_wkc_offset", label: "Logical WKC offset" },
  { value: "disconnect", label: "Disconnect slave" },
  { value: "retreat_to_safeop", label: "Retreat to SAFEOP" },
  { value: "latch_al_error", label: "Latch AL error" },
  { value: "mailbox_abort", label: "Mailbox abort" },
  { value: "mailbox_protocol_fault", label: "Mailbox protocol fault" },
];

const EXCHANGE_FAULTS = new Set([
  "drop_responses",
  "wkc_offset",
  "command_wkc_offset",
  "logical_wkc_offset",
  "disconnect",
]);

const EXCHANGE_COMMANDS = [
  "aprd",
  "apwr",
  "aprw",
  "fprd",
  "fpwr",
  "fprw",
  "brd",
  "bwr",
  "brw",
  "lrd",
  "lwr",
  "lrw",
  "armw",
  "frmw",
];

const MAILBOX_STAGES = [
  "request",
  "upload_init",
  "upload_segment",
  "download_init",
  "download_segment",
];

const MAILBOX_ABORT_STAGES = ["", "request", "upload_segment", "download_segment"];

const MAILBOX_PROTOCOL_FAULTS = [
  { value: "drop_response", label: "Drop response" },
  { value: "counter_mismatch", label: "Counter mismatch" },
  { value: "toggle_mismatch", label: "Toggle mismatch" },
  { value: "invalid_coe_payload", label: "Invalid CoE payload" },
  { value: "invalid_segment_padding", label: "Invalid segment padding" },
  { value: "mailbox_type", label: "Mailbox type" },
  { value: "coe_service", label: "CoE service" },
  { value: "sdo_command", label: "SDO command" },
  { value: "segment_command", label: "Segment command" },
];

const MILESTONE_KINDS = [
  { value: "healthy_exchanges", label: "Healthy exchanges" },
  { value: "healthy_polls", label: "Healthy polls" },
  { value: "mailbox_step", label: "Mailbox step" },
];

const UDP_MODES = [
  { value: "truncate", label: "Truncate reply" },
  { value: "unsupported_type", label: "Unsupported reply type" },
  { value: "wrong_idx", label: "Wrong datagram index" },
  { value: "replay_previous", label: "Replay previous reply" },
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

function ScheduledFaultTable({ faults }) {
  if (!faults?.length) {
    return <EmptyState>No scheduled runtime faults.</EmptyState>;
  }

  return (
    <DataTable headers={["#", "Fault", "Schedule", "Remaining"]}>
      {faults.map((fault, index) => (
        <tr key={fault.key ?? `${fault.label}-${index}`}>
          <td>
            <Mono>{index + 1}</Mono>
          </td>
          <td>
            <Mono>{fault.label}</Mono>
          </td>
          <td>
            <Mono>{fault.schedule}</Mono>
          </td>
          <td>
            <Mono>{fault.remaining}</Mono>
          </td>
        </tr>
      ))}
    </DataTable>
  );
}

function SectionCopy({ children }) {
  if (!children) return null;
  return <div className="ke95-simulator-faults-panel__copy">{children}</div>;
}

function SimulatorFaultsPanel({ ctx, data }) {
  const [snapshot, setSnapshot] = useState(data);
  const [selectedSlave, setSelectedSlave] = useState(data.slave_options?.[0] ?? "");
  const [runtimeKind, setRuntimeKind] = useState("drop_responses");
  const [runtimePlan, setRuntimePlan] = useState("immediate");
  const [runtimeValue, setRuntimeValue] = useState("0");
  const [runtimeCount, setRuntimeCount] = useState("3");
  const [runtimeDelay, setRuntimeDelay] = useState("250");
  const [runtimeCommand, setRuntimeCommand] = useState("lrw");
  const [alErrorCode, setAlErrorCode] = useState("0x001B");
  const [mailboxIndex, setMailboxIndex] = useState("0x1600");
  const [mailboxSubindex, setMailboxSubindex] = useState("0x00");
  const [mailboxAbortCode, setMailboxAbortCode] = useState("0x06010002");
  const [mailboxStage, setMailboxStage] = useState("request");
  const [mailboxAbortStage, setMailboxAbortStage] = useState("");
  const [mailboxFaultKind, setMailboxFaultKind] = useState("drop_response");
  const [mailboxFaultValue, setMailboxFaultValue] = useState("0x00");
  const [milestoneKind, setMilestoneKind] = useState("healthy_exchanges");
  const [milestoneCount, setMilestoneCount] = useState("5");
  const [milestoneStage, setMilestoneStage] = useState("request");
  const [udpMode, setUdpMode] = useState("truncate");
  const [udpPlan, setUdpPlan] = useState("next");
  const [udpCount, setUdpCount] = useState("3");
  const [udpScript, setUdpScript] = useState("truncate, wrong_idx");

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

  const runtimePlanOptions = useMemo(() => {
    if (EXCHANGE_FAULTS.has(runtimeKind)) {
      return [
        { value: "immediate", label: "Immediate" },
        { value: "next", label: "Next exchange" },
        { value: "count", label: "Next N exchanges" },
        { value: "after_ms", label: "After delay" },
        { value: "after_milestone", label: "After milestone" },
      ];
    }

    return [
      { value: "immediate", label: "Immediate" },
      { value: "after_ms", label: "After delay" },
      { value: "after_milestone", label: "After milestone" },
    ];
  }, [runtimeKind]);

  useEffect(() => {
    if (!runtimePlanOptions.some((option) => option.value === runtimePlan)) {
      setRuntimePlan(runtimePlanOptions[0]?.value ?? "immediate");
    }
  }, [runtimePlan, runtimePlanOptions]);

  const disabled = snapshot.status !== "running";
  const udpDisabled = disabled || !snapshot.udp_faults?.enabled;
  const runtimeFaults = snapshot.runtime_faults ?? {};
  const udpFaults = snapshot.udp_faults ?? {};
  const status = <StatusBadge tone={statusTone(snapshot.status)}>{snapshot.status}</StatusBadge>;

  const runtimeProperties = [
    { label: "Next exchange", value: runtimeFaults.next_label ?? "none" },
    { label: "Sticky", value: String(runtimeFaults.sticky_count ?? 0) },
    { label: "Queued", value: String(runtimeFaults.pending_count ?? 0) },
    { label: "Scheduled", value: String(runtimeFaults.scheduled_count ?? 0) },
  ];

  const udpProperties = [
    { label: "Endpoint", value: udpFaults.endpoint ?? "disabled" },
    { label: "Next reply", value: udpFaults.next_label ?? "none" },
    { label: "Queued replies", value: String(udpFaults.active_count ?? 0) },
    { label: "Captured", value: udpFaults.last_response_captured ? "yes" : "no" },
  ];

  const selectedSlaveDisabled = disabled || !selectedSlave;
  const runtimeApplyLabel = runtimePlan === "immediate" ? "Apply runtime fault" : "Queue runtime fault";
  const udpApplyLabel = udpPlan === "next" ? "Queue UDP fault" : "Apply UDP fault";
  const pushAction = (id, params = {}) => ctx.pushEvent("action", { id, ...params });

  return (
    <Shell title="Simulator faults" subtitle={snapshot.kind} status={status}>
      <Stack className="ke95-simulator-faults-panel">
        <MessageLine tone={snapshot.message?.level === "error" ? "error" : "info"}>
          {snapshot.message?.text ?? null}
        </MessageLine>

        <SummaryGrid items={snapshot.summary ?? []} />

        <Panel
          title="Quick faults"
          actions={
            <InlineButtons>
              <Button
                disabled={disabled || runtimeFaults.active_count === 0}
                onClick={() => pushAction("clear_runtime_faults")}
              >
                Clear runtime
              </Button>
              <Button
                disabled={udpDisabled || udpFaults.active_count === 0}
                onClick={() => pushAction("clear_udp_faults")}
              >
                Clear UDP
              </Button>
              <Button
                disabled={disabled || (runtimeFaults.active_count === 0 && udpFaults.active_count === 0)}
                onClick={() => pushAction("clear_faults")}
              >
                Clear all
              </Button>
            </InlineButtons>
          }
        >
          <Stack compact>
            <SectionCopy>
              Start here. These drills cover the common recovery cases without making you build a fault by hand.
            </SectionCopy>

            <Columns minWidth="18rem">
              <Stack compact className="ke95-simulator-faults-panel__quick-group">
                <div className="ke95-kicker">Runtime</div>
                <SectionCopy>Use these when you want to disturb the EtherCAT cycle itself.</SectionCopy>
                <ControlField label="Target slave">
                  <Dropdown
                    disabled={!snapshot.slave_options?.length}
                    value={selectedSlave}
                    onChange={(event) => setSelectedSlave(event.target.value)}
                  >
                    {(snapshot.slave_options ?? []).map((name) => (
                      <option key={name} value={name}>
                        {name}
                      </option>
                    ))}
                  </Dropdown>
                </ControlField>
                <InlineButtons>
                  <Button
                    disabled={disabled}
                    onClick={() =>
                      pushAction("apply_runtime_fault", {
                        kind: "drop_responses",
                        plan: "next",
                      })
                    }
                  >
                    Drop next exchange
                  </Button>
                  <Button
                    disabled={disabled}
                    onClick={() =>
                      pushAction("apply_runtime_fault", {
                        kind: "wkc_offset",
                        plan: "count",
                        value: "-1",
                        count: "3",
                      })
                    }
                  >
                    WKC -1 for 3 cycles
                  </Button>
                  <Button
                    disabled={selectedSlaveDisabled}
                    onClick={() => pushAction("inject_disconnect", { slave: selectedSlave })}
                  >
                    Disconnect slave
                  </Button>
                  <Button
                    disabled={selectedSlaveDisabled}
                    onClick={() => pushAction("retreat_to_safeop", { slave: selectedSlave })}
                  >
                    Send slave to SAFEOP
                  </Button>
                  <Button
                    disabled={selectedSlaveDisabled}
                    onClick={() =>
                      pushAction("inject_al_error", {
                        slave: selectedSlave,
                        code: "0x001B",
                      })
                    }
                  >
                    Latch AL error
                  </Button>
                </InlineButtons>
              </Stack>

              <Stack compact className="ke95-simulator-faults-panel__quick-group">
                <div className="ke95-kicker">UDP</div>
                <SectionCopy>Use these when you only want to disturb the transport replies.</SectionCopy>
                <InlineButtons>
                  <Button
                    disabled={udpDisabled}
                    onClick={() =>
                      pushAction("apply_udp_fault", {
                        mode: "truncate",
                        plan: "next",
                      })
                    }
                  >
                    Truncate next reply
                  </Button>
                  <Button
                    disabled={udpDisabled}
                    onClick={() =>
                      pushAction("apply_udp_fault", {
                        mode: "wrong_idx",
                        plan: "count",
                        count: "3",
                      })
                    }
                  >
                    Wrong index for 3 replies
                  </Button>
                  <Button
                    disabled={udpDisabled}
                    onClick={() =>
                      pushAction("apply_udp_fault", {
                        mode: "replay_previous",
                        plan: "next",
                      })
                    }
                  >
                    Replay previous reply
                  </Button>
                </InlineButtons>
              </Stack>
            </Columns>
          </Stack>
        </Panel>

        <Panel title="Current fault state">
          <Stack compact>
            <Columns minWidth="18rem">
              <Stack compact>
                <div className="ke95-kicker">Runtime</div>
                <SectionCopy>{runtimeFaults.summary ?? "No runtime faults."}</SectionCopy>
                <PropertyList items={runtimeProperties} />
              </Stack>

              <Stack compact>
                <div className="ke95-kicker">UDP</div>
                <SectionCopy>{udpFaults.summary ?? "UDP disabled."}</SectionCopy>
                <PropertyList items={udpProperties} />
              </Stack>
            </Columns>

            <Stack compact className="ke95-simulator-faults-panel__tables">
              <div className="ke95-simulator-faults-panel__table-section">
                <div className="ke95-kicker">Sticky runtime faults</div>
                <SectionCopy>These are active now and stay active until you clear them.</SectionCopy>
                <FaultTable
                  labels={runtimeFaults.sticky_labels}
                  emptyText="No sticky runtime faults are active."
                />
              </div>

              <div className="ke95-simulator-faults-panel__table-section">
                <div className="ke95-kicker">Queued exchange faults</div>
                <SectionCopy>These will run on the next exchanges that match your plan.</SectionCopy>
                <FaultTable
                  labels={runtimeFaults.pending_labels}
                  emptyText="No runtime exchange faults are queued."
                />
              </div>

              <div className="ke95-simulator-faults-panel__table-section">
                <div className="ke95-kicker">Scheduled runtime faults</div>
                <SectionCopy>These are waiting for a delay or milestone before they become active.</SectionCopy>
                <ScheduledFaultTable faults={runtimeFaults.scheduled_faults} />
              </div>

              <div className="ke95-simulator-faults-panel__table-section">
                <div className="ke95-kicker">Queued UDP reply faults</div>
                <SectionCopy>These affect future UDP replies without changing simulator state directly.</SectionCopy>
                <FaultTable
                  labels={udpFaults.pending_labels}
                  emptyText="No UDP reply faults are queued."
                />
              </div>
            </Stack>
          </Stack>
        </Panel>

        <Panel title="Advanced runtime builder">
          <Stack compact>
            <SectionCopy>
              Use this when the quick drills are not enough. It maps closely to the simulator fault API.
            </SectionCopy>

            <Columns minWidth="12rem">
              <ControlField label="Fault">
                <Dropdown value={runtimeKind} onChange={(event) => setRuntimeKind(event.target.value)}>
                  {RUNTIME_FAULTS.map((option) => (
                    <option key={option.value} value={option.value}>
                      {option.label}
                    </option>
                  ))}
                </Dropdown>
              </ControlField>

              <ControlField label="Plan">
                <Dropdown value={runtimePlan} onChange={(event) => setRuntimePlan(event.target.value)}>
                  {runtimePlanOptions.map((option) => (
                    <option key={option.value} value={option.value}>
                      {option.label}
                    </option>
                  ))}
                </Dropdown>
              </ControlField>

              {runtimeKind === "command_wkc_offset" ? (
                <ControlField label="Command">
                  <Dropdown value={runtimeCommand} onChange={(event) => setRuntimeCommand(event.target.value)}>
                    {EXCHANGE_COMMANDS.map((command) => (
                      <option key={command} value={command}>
                        {command}
                      </option>
                    ))}
                  </Dropdown>
                </ControlField>
              ) : null}

              {[
                "logical_wkc_offset",
                "disconnect",
                "retreat_to_safeop",
                "latch_al_error",
                "mailbox_abort",
                "mailbox_protocol_fault",
              ].includes(runtimeKind) ? (
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

              {["wkc_offset", "command_wkc_offset", "logical_wkc_offset"].includes(runtimeKind) ? (
                <ControlField label="Offset">
                  <Input value={runtimeValue} onChange={(event) => setRuntimeValue(event.target.value)} />
                </ControlField>
              ) : null}

              {runtimeKind === "latch_al_error" ? (
                <ControlField label="AL error code">
                  <Input value={alErrorCode} onChange={(event) => setAlErrorCode(event.target.value)} />
                </ControlField>
              ) : null}

              {["mailbox_abort", "mailbox_protocol_fault"].includes(runtimeKind) ? (
                <ControlField label="Mailbox index">
                  <Input value={mailboxIndex} onChange={(event) => setMailboxIndex(event.target.value)} />
                </ControlField>
              ) : null}

              {["mailbox_abort", "mailbox_protocol_fault"].includes(runtimeKind) ? (
                <ControlField label="Subindex">
                  <Input value={mailboxSubindex} onChange={(event) => setMailboxSubindex(event.target.value)} />
                </ControlField>
              ) : null}

              {runtimeKind === "mailbox_abort" ? (
                <ControlField label="Abort code">
                  <Input value={mailboxAbortCode} onChange={(event) => setMailboxAbortCode(event.target.value)} />
                </ControlField>
              ) : null}

              {runtimeKind === "mailbox_abort" ? (
                <ControlField label="Abort stage">
                  <Dropdown value={mailboxAbortStage} onChange={(event) => setMailboxAbortStage(event.target.value)}>
                    {MAILBOX_ABORT_STAGES.map((stage) => (
                      <option key={stage || "any"} value={stage}>
                        {stage || "any"}
                      </option>
                    ))}
                  </Dropdown>
                </ControlField>
              ) : null}

              {runtimeKind === "mailbox_protocol_fault" ? (
                <ControlField label="Mailbox stage">
                  <Dropdown value={mailboxStage} onChange={(event) => setMailboxStage(event.target.value)}>
                    {MAILBOX_STAGES.map((stage) => (
                      <option key={stage} value={stage}>
                        {stage}
                      </option>
                    ))}
                  </Dropdown>
                </ControlField>
              ) : null}

              {runtimeKind === "mailbox_protocol_fault" ? (
                <ControlField label="Protocol fault">
                  <Dropdown value={mailboxFaultKind} onChange={(event) => setMailboxFaultKind(event.target.value)}>
                    {MAILBOX_PROTOCOL_FAULTS.map((option) => (
                      <option key={option.value} value={option.value}>
                        {option.label}
                      </option>
                    ))}
                  </Dropdown>
                </ControlField>
              ) : null}

              {runtimeKind === "mailbox_protocol_fault" &&
              ["mailbox_type", "coe_service", "sdo_command", "segment_command"].includes(mailboxFaultKind) ? (
                <ControlField label="Protocol value">
                  <Input value={mailboxFaultValue} onChange={(event) => setMailboxFaultValue(event.target.value)} />
                </ControlField>
              ) : null}

              {runtimePlan === "count" ? (
                <ControlField label="Count">
                  <Input value={runtimeCount} onChange={(event) => setRuntimeCount(event.target.value)} />
                </ControlField>
              ) : null}

              {runtimePlan === "after_ms" ? (
                <ControlField label="Delay ms">
                  <Input value={runtimeDelay} onChange={(event) => setRuntimeDelay(event.target.value)} />
                </ControlField>
              ) : null}

              {runtimePlan === "after_milestone" ? (
                <ControlField label="Milestone">
                  <Dropdown value={milestoneKind} onChange={(event) => setMilestoneKind(event.target.value)}>
                    {MILESTONE_KINDS.map((option) => (
                      <option key={option.value} value={option.value}>
                        {option.label}
                      </option>
                    ))}
                  </Dropdown>
                </ControlField>
              ) : null}

              {runtimePlan === "after_milestone" ? (
                <ControlField label="Milestone count">
                  <Input value={milestoneCount} onChange={(event) => setMilestoneCount(event.target.value)} />
                </ControlField>
              ) : null}

              {runtimePlan === "after_milestone" && milestoneKind !== "healthy_exchanges" ? (
                <ControlField label="Milestone slave">
                  <Dropdown value={selectedSlave} onChange={(event) => setSelectedSlave(event.target.value)}>
                    {(snapshot.slave_options ?? []).map((name) => (
                      <option key={name} value={name}>
                        {name}
                      </option>
                    ))}
                  </Dropdown>
                </ControlField>
              ) : null}

              {runtimePlan === "after_milestone" && milestoneKind === "mailbox_step" ? (
                <ControlField label="Milestone stage">
                  <Dropdown value={milestoneStage} onChange={(event) => setMilestoneStage(event.target.value)}>
                    {MAILBOX_STAGES.map((stage) => (
                      <option key={stage} value={stage}>
                        {stage}
                      </option>
                    ))}
                  </Dropdown>
                </ControlField>
              ) : null}

              <InlineButtons className="ke95-simulator-faults-panel__row-actions">
                <Button
                  disabled={disabled}
                  onClick={() =>
                    pushAction("apply_runtime_fault", {
                      kind: runtimeKind,
                      plan: runtimePlan,
                      command: runtimeCommand,
                      slave: selectedSlave,
                      value: runtimeValue,
                      count: runtimeCount,
                      delay_ms: runtimeDelay,
                      code: alErrorCode,
                      index: mailboxIndex,
                      subindex: mailboxSubindex,
                      abort_code: mailboxAbortCode,
                      stage: runtimeKind === "mailbox_abort" ? mailboxAbortStage : mailboxStage,
                      mailbox_fault_kind: mailboxFaultKind,
                      mailbox_fault_value: mailboxFaultValue,
                      milestone_kind: milestoneKind,
                      milestone_count: milestoneCount,
                      milestone_slave: selectedSlave,
                      milestone_stage: milestoneStage,
                    })
                  }
                >
                  {runtimeApplyLabel}
                </Button>
              </InlineButtons>
            </Columns>
          </Stack>
        </Panel>

        <Panel title="Advanced UDP builder">
          <Stack compact>
            <SectionCopy>
              Keep this for transport-specific cases like scripts, truncation, and wrong datagram indexes.
            </SectionCopy>

            <Columns minWidth="12rem">
              <ControlField label="Reply fault">
                <Dropdown value={udpMode} onChange={(event) => setUdpMode(event.target.value)}>
                  {UDP_MODES.map((option) => (
                    <option key={option.value} value={option.value}>
                      {option.label}
                    </option>
                  ))}
                </Dropdown>
              </ControlField>

              <ControlField label="Plan">
                <Dropdown value={udpPlan} onChange={(event) => setUdpPlan(event.target.value)}>
                  <option value="next">Next reply</option>
                  <option value="count">Next N replies</option>
                  <option value="script">Script</option>
                </Dropdown>
              </ControlField>

              {udpPlan === "count" ? (
                <ControlField label="Count">
                  <Input value={udpCount} onChange={(event) => setUdpCount(event.target.value)} />
                </ControlField>
              ) : null}

              {udpPlan === "script" ? (
                <ControlField label="Script">
                  <TextArea
                    rows={3}
                    className="ke95-simulator-faults-panel__script"
                    value={udpScript}
                    onChange={(event) => setUdpScript(event.target.value)}
                  />
                </ControlField>
              ) : null}

              <InlineButtons className="ke95-simulator-faults-panel__row-actions">
                <Button
                  disabled={udpDisabled}
                  onClick={() =>
                    pushAction("apply_udp_fault", {
                      mode: udpMode,
                      plan: udpPlan,
                      count: udpCount,
                      script: udpScript,
                    })
                  }
                >
                  {udpApplyLabel}
                </Button>
              </InlineButtons>
            </Columns>
          </Stack>
        </Panel>
      </Stack>
    </Shell>
  );
}
