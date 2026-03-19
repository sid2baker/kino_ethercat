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
  Tab,
  Tabs,
  TextArea,
} from "../../ui/react95";

const SLAVE_RUNTIME_FAULTS = [
  { value: "logical_wkc_offset", label: "Logical WKC offset" },
  { value: "disconnect", label: "Disconnect slave" },
  { value: "retreat_to_safeop", label: "Retreat to SAFEOP" },
  { value: "latch_al_error", label: "Latch AL error" },
  { value: "mailbox_abort", label: "Mailbox abort" },
  { value: "mailbox_protocol_fault", label: "Mailbox protocol fault" },
];

const BUS_RUNTIME_FAULTS = [
  { value: "drop_responses", label: "Drop responses" },
  { value: "wkc_offset", label: "WKC offset" },
  { value: "command_wkc_offset", label: "Command WKC offset" },
];

const SLAVE_RUNTIME_FAULT_VALUES = new Set(SLAVE_RUNTIME_FAULTS.map((option) => option.value));
const BUS_RUNTIME_FAULT_VALUES = new Set(BUS_RUNTIME_FAULTS.map((option) => option.value));

const EXCHANGE_FAULTS = new Set([
  "drop_responses",
  "wkc_offset",
  "command_wkc_offset",
  "logical_wkc_offset",
  "disconnect",
]);

const OFFSET_RUNTIME_FAULTS = new Set([
  "wkc_offset",
  "command_wkc_offset",
  "logical_wkc_offset",
]);

const MAILBOX_VALUE_FAULTS = new Set([
  "mailbox_type",
  "coe_service",
  "sdo_command",
  "segment_command",
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

const SLAVE_MILESTONE_KINDS = [
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

const UDP_MODE_VALUES = new Set(UDP_MODES.map((option) => option.value));
const EMPTY_VALIDATION = { errors: [], warnings: [] };

export async function init(ctx, data) {
  await ctx.importCSS("main.css");
  const root = createRoot(ctx.root);
  root.render(<SimulatorFaultsPanel ctx={ctx} data={data} />);
}

function statusTone(status) {
  return status === "running" ? "ok" : status === "offline" ? "neutral" : "warn";
}

function trimValue(value) {
  return String(value ?? "").trim();
}

function chooseOption(value, options) {
  if (!options.length) return "";
  return options.includes(value) ? value : options[0];
}

function isSignedInteger(value) {
  return /^-?\d+$/.test(trimValue(value));
}

function isPositiveInteger(value) {
  return /^[1-9]\d*$/.test(trimValue(value));
}

function isNonNegativeInteger(value, { allowBlank = true } = {}) {
  const trimmed = trimValue(value);

  if (trimmed === "") {
    return allowBlank;
  }

  if (/^0x[0-9a-f]+$/i.test(trimmed)) {
    return true;
  }

  return /^\d+$/.test(trimmed);
}

function runtimePlanOptions(kind) {
  if (EXCHANGE_FAULTS.has(kind)) {
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
}

function runtimeDraftDefaults(defaultSlave = "") {
  return {
    faultKind: "drop_responses",
    plan: "next",
    targetSlave: defaultSlave,
    value: "0",
    count: "3",
    delayMs: "250",
    command: "lrw",
    alErrorCode: "0x001B",
    mailboxIndex: "0x1600",
    mailboxSubindex: "0x00",
    mailboxAbortCode: "0x06010002",
    mailboxStage: "request",
    mailboxAbortStage: "",
    mailboxFaultKind: "drop_response",
    mailboxFaultValue: "0x00",
    milestoneKind: "healthy_exchanges",
    milestoneCount: "5",
    milestoneSlave: defaultSlave,
    milestoneStage: "request",
  };
}

function transportDraftDefaults(transportFaults) {
  if (transportFaults.transport === "raw") {
    return {
      kind: "delay_response",
      delayMs: "75",
      endpoint: transportFaults.mode === "redundant" ? "all" : "primary",
      fromIngress: "all",
    };
  }

  return {
    mode: "truncate",
    plan: "next",
    count: "3",
    script: "truncate, wrong_idx",
  };
}

function offlineTransportFaults() {
  return {
    enabled: false,
    transport: "disabled",
    title: "Transport faults",
    active_count: 0,
    next_label: null,
    summary: "Transport fault injection unavailable.",
    endpoints: [],
    mode: null,
    pending_labels: [],
    endpoint: "disabled",
    last_response_captured: false,
  };
}

function normalizeSlaveDraft(draft, selectedSlave) {
  const normalized = {
    ...runtimeDraftDefaults(selectedSlave),
    ...draft,
    targetSlave: selectedSlave,
    milestoneSlave: selectedSlave,
  };

  if (!SLAVE_RUNTIME_FAULT_VALUES.has(normalized.faultKind)) {
    normalized.faultKind = SLAVE_RUNTIME_FAULTS[0].value;
  }

  const plans = runtimePlanOptions(normalized.faultKind).map((option) => option.value);
  normalized.plan = plans.includes(normalized.plan) ? normalized.plan : plans[0];

  return normalized;
}

function normalizeBusDraft(draft) {
  const normalized = {
    ...runtimeDraftDefaults(""),
    ...draft,
    targetSlave: "",
    milestoneSlave: "",
  };

  if (!BUS_RUNTIME_FAULT_VALUES.has(normalized.faultKind)) {
    normalized.faultKind = BUS_RUNTIME_FAULTS[0].value;
  }

  const plans = runtimePlanOptions(normalized.faultKind).map((option) => option.value);
  normalized.plan = plans.includes(normalized.plan) ? normalized.plan : plans[0];
  normalized.milestoneKind = "healthy_exchanges";

  return normalized;
}

function rawEndpointOptions(mode) {
  if (mode === "redundant") {
    return [
      { value: "all", label: "All endpoints" },
      { value: "primary", label: "Primary" },
      { value: "secondary", label: "Secondary" },
    ];
  }

  return [{ value: "primary", label: "Primary" }];
}

function rawIngressOptions(mode) {
  if (mode === "redundant") {
    return [
      { value: "all", label: "All ingress" },
      { value: "primary", label: "Primary ingress" },
      { value: "secondary", label: "Secondary ingress" },
    ];
  }

  return [
    { value: "all", label: "All ingress" },
    { value: "primary", label: "Primary ingress" },
  ];
}

function normalizeTransportDraft(draft, transportFaults) {
  const normalized = {
    ...transportDraftDefaults(transportFaults),
    ...draft,
  };

  if (transportFaults.transport === "raw") {
    const endpointOptions = rawEndpointOptions(transportFaults.mode);
    const ingressOptions = rawIngressOptions(transportFaults.mode);

    normalized.endpoint = chooseOption(
      normalized.endpoint,
      endpointOptions.map((option) => option.value)
    );
    normalized.fromIngress = chooseOption(
      normalized.fromIngress,
      ingressOptions.map((option) => option.value)
    );

    return normalized;
  }

  normalized.plan = ["next", "count", "script"].includes(normalized.plan) ? normalized.plan : "next";
  return normalized;
}

function validateSlaveDraft(draft, selectedSlave) {
  const errors = [];
  const warnings = [];

  if (!selectedSlave) {
    errors.push("Select a simulator slave.");
  }

  if (!SLAVE_RUNTIME_FAULT_VALUES.has(draft.faultKind)) {
    errors.push("Select a slave fault.");
  }

  if (OFFSET_RUNTIME_FAULTS.has(draft.faultKind) && !isSignedInteger(draft.value)) {
    errors.push("Offsets must be decimal integers.");
  }

  if (draft.faultKind === "latch_al_error" && !isNonNegativeInteger(draft.alErrorCode)) {
    errors.push("AL error codes must be decimal or 0x-prefixed hex.");
  }

  if (["mailbox_abort", "mailbox_protocol_fault"].includes(draft.faultKind)) {
    if (!isNonNegativeInteger(draft.mailboxIndex)) {
      errors.push("Mailbox index must be decimal or 0x-prefixed hex.");
    }

    if (!isNonNegativeInteger(draft.mailboxSubindex)) {
      errors.push("Mailbox subindex must be decimal or 0x-prefixed hex.");
    }
  }

  if (draft.faultKind === "mailbox_abort") {
    if (!MAILBOX_ABORT_STAGES.includes(draft.mailboxAbortStage)) {
      errors.push("Select a valid mailbox abort stage.");
    }

    if (!isNonNegativeInteger(draft.mailboxAbortCode)) {
      errors.push("Abort code must be decimal or 0x-prefixed hex.");
    }
  }

  if (draft.faultKind === "mailbox_protocol_fault") {
    if (!MAILBOX_STAGES.includes(draft.mailboxStage)) {
      errors.push("Select a valid mailbox stage.");
    }

    if (!MAILBOX_PROTOCOL_FAULTS.some((option) => option.value === draft.mailboxFaultKind)) {
      errors.push("Select a valid mailbox protocol fault.");
    }

    if (MAILBOX_VALUE_FAULTS.has(draft.mailboxFaultKind) && !isNonNegativeInteger(draft.mailboxFaultValue)) {
      errors.push("Protocol fault value must be decimal or 0x-prefixed hex.");
    }
  }

  if (draft.plan === "count" && !isPositiveInteger(draft.count)) {
    errors.push("Counts must be positive integers.");
  }

  if (draft.plan === "after_ms" && !isNonNegativeInteger(draft.delayMs, { allowBlank: false })) {
    errors.push("Delay must be a non-negative integer.");
  }

  if (draft.plan === "after_milestone") {
    if (!isPositiveInteger(draft.milestoneCount)) {
      errors.push("Milestone counts must be positive integers.");
    }

    if (!SLAVE_MILESTONE_KINDS.some((option) => option.value === draft.milestoneKind)) {
      errors.push("Select a valid milestone.");
    }

    if (draft.milestoneKind === "mailbox_step" && !MAILBOX_STAGES.includes(draft.milestoneStage)) {
      errors.push("Select a valid milestone stage.");
    }
  }

  if (draft.plan === "immediate") {
    warnings.push("Immediate faults arm as soon as you apply them.");
  }

  return { errors, warnings };
}

function validateBusDraft(draft) {
  const errors = [];
  const warnings = [];

  if (!BUS_RUNTIME_FAULT_VALUES.has(draft.faultKind)) {
    errors.push("Select a bus fault.");
  }

  if (draft.faultKind === "command_wkc_offset" && !EXCHANGE_COMMANDS.includes(draft.command)) {
    errors.push("Select a valid EtherCAT command.");
  }

  if (OFFSET_RUNTIME_FAULTS.has(draft.faultKind) && !isSignedInteger(draft.value)) {
    errors.push("Offsets must be decimal integers.");
  }

  if (draft.plan === "count" && !isPositiveInteger(draft.count)) {
    errors.push("Counts must be positive integers.");
  }

  if (draft.plan === "after_ms" && !isNonNegativeInteger(draft.delayMs, { allowBlank: false })) {
    errors.push("Delay must be a non-negative integer.");
  }

  if (draft.plan === "after_milestone" && !isPositiveInteger(draft.milestoneCount)) {
    errors.push("Milestone counts must be positive integers.");
  }

  if (draft.plan === "immediate") {
    warnings.push("Immediate faults arm as soon as you apply them.");
  }

  return { errors, warnings };
}

function validateTransportDraft(draft, transportFaults) {
  const errors = [];
  const warnings = [];

  if (!transportFaults.enabled) {
    errors.push("Transport fault injection is unavailable.");
    return { errors, warnings };
  }

  if (transportFaults.transport === "raw") {
    const endpointOptions = rawEndpointOptions(transportFaults.mode).map((option) => option.value);
    const ingressOptions = rawIngressOptions(transportFaults.mode).map((option) => option.value);

    if (!isNonNegativeInteger(draft.delayMs, { allowBlank: false })) {
      errors.push("Delay must be a non-negative integer.");
    }

    if (!endpointOptions.includes(draft.endpoint)) {
      errors.push("Select a valid raw endpoint.");
    }

    if (!ingressOptions.includes(draft.fromIngress)) {
      errors.push("Select a valid ingress filter.");
    }

    if (trimValue(draft.delayMs) === "0") {
      warnings.push("A zero millisecond delay effectively clears the raw delay fault.");
    }

    return { errors, warnings };
  }

  if (draft.plan === "count" && !isPositiveInteger(draft.count)) {
    errors.push("Reply counts must be positive integers.");
  }

  if (draft.plan === "script") {
    const tokens = trimValue(draft.script)
      .split(/[\s,]+/)
      .map((token) => token.trim())
      .filter(Boolean);

    if (!tokens.length) {
      errors.push("Provide at least one script step.");
    } else if (tokens.some((token) => !UDP_MODE_VALUES.has(token))) {
      errors.push("Script steps must use known UDP fault names.");
    }
  }

  if (draft.plan === "next") {
    warnings.push("Next reply faults are consumed by the first matching reply.");
  }

  return { errors, warnings };
}

function buildRuntimeAction(draft) {
  const params = {
    kind: draft.faultKind,
    plan: draft.plan,
  };

  if (draft.faultKind === "command_wkc_offset") {
    params.command = draft.command;
  }

  if (SLAVE_RUNTIME_FAULT_VALUES.has(draft.faultKind)) {
    params.slave = draft.targetSlave;
  }

  if (OFFSET_RUNTIME_FAULTS.has(draft.faultKind)) {
    params.value = draft.value;
  }

  if (draft.faultKind === "latch_al_error") {
    params.code = draft.alErrorCode;
  }

  if (["mailbox_abort", "mailbox_protocol_fault"].includes(draft.faultKind)) {
    params.index = draft.mailboxIndex;
    params.subindex = draft.mailboxSubindex;
  }

  if (draft.faultKind === "mailbox_abort") {
    params.abort_code = draft.mailboxAbortCode;
    params.stage = draft.mailboxAbortStage;
  }

  if (draft.faultKind === "mailbox_protocol_fault") {
    params.stage = draft.mailboxStage;
    params.mailbox_fault_kind = draft.mailboxFaultKind;

    if (MAILBOX_VALUE_FAULTS.has(draft.mailboxFaultKind)) {
      params.mailbox_fault_value = draft.mailboxFaultValue;
    }
  }

  if (draft.plan === "count") {
    params.count = draft.count;
  }

  if (draft.plan === "after_ms") {
    params.delay_ms = draft.delayMs;
  }

  if (draft.plan === "after_milestone") {
    params.milestone_kind = draft.milestoneKind;
    params.milestone_count = draft.milestoneCount;

    if (draft.milestoneKind !== "healthy_exchanges") {
      params.milestone_slave = draft.milestoneSlave;
    }

    if (draft.milestoneKind === "mailbox_step") {
      params.milestone_stage = draft.milestoneStage;
    }
  }

  return { id: "apply_runtime_fault", params };
}

function buildUdpTransportAction(draft) {
  const params = {
    transport: "udp",
    mode: draft.mode,
    plan: draft.plan,
  };

  if (draft.plan === "count") {
    params.count = draft.count;
  }

  if (draft.plan === "script") {
    params.script = draft.script;
  }

  return { id: "apply_transport_fault", params };
}

function buildRawTransportAction(draft) {
  return {
    id: "apply_transport_fault",
    params: {
      transport: "raw",
      kind: "delay_response",
      delay_ms: draft.delayMs,
      endpoint: draft.endpoint,
      from_ingress: draft.fromIngress,
    },
  };
}

function buildTransportAction(draft, transportFaults) {
  if (!transportFaults.enabled) return null;
  return transportFaults.transport === "raw" ? buildRawTransportAction(draft) : buildUdpTransportAction(draft);
}

function atomLiteral(value) {
  return `:${trimValue(value)}`;
}

function literalValue(value, fallback = "0") {
  const trimmed = trimValue(value);
  return trimmed === "" ? fallback : trimmed;
}

function buildMailboxProtocolFaultExpression(draft) {
  switch (draft.mailboxFaultKind) {
    case "drop_response":
      return ":drop_response";
    case "counter_mismatch":
      return ":counter_mismatch";
    case "toggle_mismatch":
      return ":toggle_mismatch";
    case "invalid_coe_payload":
      return ":invalid_coe_payload";
    case "invalid_segment_padding":
      return ":invalid_segment_padding";
    case "mailbox_type":
      return `{:mailbox_type, ${literalValue(draft.mailboxFaultValue)}}`;
    case "coe_service":
      return `{:coe_service, ${literalValue(draft.mailboxFaultValue)}}`;
    case "sdo_command":
      return `{:sdo_command, ${literalValue(draft.mailboxFaultValue)}}`;
    case "segment_command":
      return `{:segment_command, ${literalValue(draft.mailboxFaultValue)}}`;
    default:
      return null;
  }
}

function buildRuntimeMilestoneExpression(draft) {
  switch (draft.milestoneKind) {
    case "healthy_exchanges":
      return `Fault.healthy_exchanges(${literalValue(draft.milestoneCount, "1")})`;
    case "healthy_polls":
      return `Fault.healthy_polls(${atomLiteral(draft.milestoneSlave)}, ${literalValue(draft.milestoneCount, "1")})`;
    case "mailbox_step":
      return `Fault.mailbox_step(${atomLiteral(draft.milestoneSlave)}, ${atomLiteral(draft.milestoneStage)}, ${literalValue(draft.milestoneCount, "1")})`;
    default:
      return null;
  }
}

function buildRuntimeEffectExpression(draft) {
  switch (draft.faultKind) {
    case "drop_responses":
      return "Fault.drop_responses()";
    case "wkc_offset":
      return `Fault.wkc_offset(${literalValue(draft.value)})`;
    case "command_wkc_offset":
      return `Fault.command_wkc_offset(${atomLiteral(draft.command)}, ${literalValue(draft.value)})`;
    case "logical_wkc_offset":
      return `Fault.logical_wkc_offset(${atomLiteral(draft.targetSlave)}, ${literalValue(draft.value)})`;
    case "disconnect":
      return `Fault.disconnect(${atomLiteral(draft.targetSlave)})`;
    case "retreat_to_safeop":
      return `Fault.retreat_to_safeop(${atomLiteral(draft.targetSlave)})`;
    case "latch_al_error":
      return `Fault.latch_al_error(${atomLiteral(draft.targetSlave)}, ${literalValue(draft.alErrorCode)})`;
    case "mailbox_abort":
      if (trimValue(draft.mailboxAbortStage) === "") {
        return `Fault.mailbox_abort(${atomLiteral(draft.targetSlave)}, ${literalValue(draft.mailboxIndex)}, ${literalValue(draft.mailboxSubindex)}, ${literalValue(draft.mailboxAbortCode)})`;
      }

      return `Fault.mailbox_abort(${atomLiteral(draft.targetSlave)}, ${literalValue(draft.mailboxIndex)}, ${literalValue(draft.mailboxSubindex)}, ${literalValue(draft.mailboxAbortCode)}, stage: ${atomLiteral(draft.mailboxAbortStage)})`;
    case "mailbox_protocol_fault": {
      const protocolFault = buildMailboxProtocolFaultExpression(draft);
      if (!protocolFault) return null;

      return `Fault.mailbox_protocol_fault(${atomLiteral(draft.targetSlave)}, ${literalValue(draft.mailboxIndex)}, ${literalValue(draft.mailboxSubindex)}, ${atomLiteral(draft.mailboxStage)}, ${protocolFault})`;
    }
    default:
      return null;
  }
}

function buildRuntimeExpression(draft) {
  const effect = buildRuntimeEffectExpression(draft);

  if (!effect) return null;

  switch (draft.plan) {
    case "immediate":
      return effect;
    case "next":
      return `Fault.next(${effect})`;
    case "count":
      return `Fault.next(${effect}, ${literalValue(draft.count, "1")})`;
    case "after_ms":
      return `Fault.after_ms(${effect}, ${literalValue(draft.delayMs, "0")})`;
    case "after_milestone": {
      const milestone = buildRuntimeMilestoneExpression(draft);
      return milestone ? `Fault.after_milestone(${effect}, ${milestone})` : null;
    }
    default:
      return null;
  }
}

function udpModeExpression(mode) {
  switch (mode) {
    case "truncate":
      return "Fault.truncate()";
    case "unsupported_type":
      return "Fault.unsupported_type()";
    case "wrong_idx":
      return "Fault.wrong_idx()";
    case "replay_previous":
      return "Fault.replay_previous()";
    default:
      return null;
  }
}

function buildUdpTransportExpression(draft) {
  switch (draft.plan) {
    case "next":
      return udpModeExpression(draft.mode);
    case "count": {
      const mode = udpModeExpression(draft.mode);
      return mode ? `Fault.next(${mode}, ${literalValue(draft.count, "1")})` : null;
    }
    case "script": {
      const steps = trimValue(draft.script)
        .split(/[\s,]+/)
        .map((token) => token.trim())
        .filter(Boolean)
        .map(udpModeExpression);

      if (!steps.length || steps.some((step) => step == null)) {
        return null;
      }

      return `Fault.script([${steps.join(", ")}])`;
    }
    default:
      return null;
  }
}

function buildRawTransportExpression(draft, transportFaults) {
  const options = [];
  const mode = transportFaults.mode ?? "single";

  if (mode === "redundant" && draft.endpoint !== "all") {
    options.push(`endpoint: ${atomLiteral(draft.endpoint)}`);
  }

  if (draft.fromIngress !== "all") {
    options.push(`from_ingress: ${atomLiteral(draft.fromIngress)}`);
  }

  if (options.length) {
    return `Fault.delay_response(${literalValue(draft.delayMs, "0")}, ${options.join(", ")})`;
  }

  return `Fault.delay_response(${literalValue(draft.delayMs, "0")})`;
}

function buildRuntimeSnippet(draft) {
  const expression = buildRuntimeExpression(draft);
  if (!expression) return null;

  return [
    "alias EtherCAT.Simulator",
    "alias EtherCAT.Simulator.Fault",
    "",
    ":ok =",
    "  Simulator.inject_fault(",
    `    ${expression}`,
    "  )",
  ].join("\n");
}

function buildTransportSnippet(draft, transportFaults) {
  if (!transportFaults.enabled) return null;

  if (transportFaults.transport === "raw") {
    const expression = buildRawTransportExpression(draft, transportFaults);

    if (!expression) return null;

    return [
      "alias EtherCAT.Simulator.Transport.Raw",
      "alias EtherCAT.Simulator.Transport.Raw.Fault",
      "",
      ":ok =",
      "  Raw.inject_fault(",
      `    ${expression}`,
      "  )",
    ].join("\n");
  }

  const expression = buildUdpTransportExpression(draft);

  if (!expression) return null;

  return [
    "alias EtherCAT.Simulator.Transport.Udp",
    "alias EtherCAT.Simulator.Transport.Udp.Fault",
    "",
    ":ok =",
    "  Udp.inject_fault(",
    `    ${expression}`,
    "  )",
  ].join("\n");
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

function RawTransportTable({ endpoints }) {
  if (!endpoints?.length) {
    return <EmptyState>No raw endpoints are active.</EmptyState>;
  }

  return (
    <DataTable headers={["Endpoint", "Interface", "Delay", "Ingress", "Active"]}>
      {endpoints.map((endpoint) => (
        <tr key={endpoint.key}>
          <td>
            <Mono>{endpoint.endpoint}</Mono>
          </td>
          <td>
            <Mono>{endpoint.interface}</Mono>
          </td>
          <td>
            <Mono>{`${endpoint.response_delay_ms} ms`}</Mono>
          </td>
          <td>
            <Mono>{endpoint.response_delay_from_ingress}</Mono>
          </td>
          <td>
            <StatusBadge tone={endpoint.active ? "warn" : "neutral"}>
              {endpoint.active ? "active" : "clear"}
            </StatusBadge>
          </td>
        </tr>
      ))}
    </DataTable>
  );
}

function SectionCopy({ children }) {
  if (!children) return null;
  return <div>{children}</div>;
}

function WatchList({ items = [] }) {
  if (!items.length) return null;

  return (
    <Stack compact>
      {items.map((item) => (
        <MessageLine key={item} tone="info">
          {item}
        </MessageLine>
      ))}
    </Stack>
  );
}

function DrillGroup({ title, copy, watch = [], children }) {
  return (
    <Panel title={title}>
      <Stack compact>
        <SectionCopy>{copy}</SectionCopy>
        <WatchList items={watch} />
        {children}
      </Stack>
    </Panel>
  );
}

function CodeBlock({ code }) {
  if (!code) {
    return <EmptyState>No code preview available.</EmptyState>;
  }

  return (
    <pre style={{ margin: 0, whiteSpace: "pre-wrap" }}>
      <Mono as="span">{code}</Mono>
    </pre>
  );
}

function ValidationMessages({ validation }) {
  return (
    <Stack compact>
      {validation.errors.map((error) => (
        <MessageLine key={error} tone="error">
          {error}
        </MessageLine>
      ))}

      {validation.warnings.map((warning) => (
        <MessageLine key={warning} tone="info">
          {warning}
        </MessageLine>
      ))}
    </Stack>
  );
}

function ActionPreview({ action }) {
  if (!action) {
    return <EmptyState>No action available.</EmptyState>;
  }

  return (
    <Stack compact>
      <Mono>{action.id}</Mono>
      <CodeBlock code={JSON.stringify(action.params, null, 2)} />
    </Stack>
  );
}

function SlaveFaultEditor({ selectedSlave, slaveOptions, draft, onSelectSlave, onChange }) {
  const planOptions = runtimePlanOptions(draft.faultKind);

  return (
    <Stack compact>
      <ControlField label="Target slave">
        <Dropdown value={selectedSlave} disabled={!slaveOptions.length} onChange={(event) => onSelectSlave(event.target.value)}>
          {slaveOptions.map((name) => (
            <option key={name} value={name}>
              {name}
            </option>
          ))}
        </Dropdown>
      </ControlField>

      <Columns minWidth="12rem">
        <ControlField label="Fault">
          <Dropdown value={draft.faultKind} onChange={(event) => onChange({ faultKind: event.target.value })}>
            {SLAVE_RUNTIME_FAULTS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </Dropdown>
        </ControlField>

        <ControlField label="Plan">
          <Dropdown value={draft.plan} onChange={(event) => onChange({ plan: event.target.value })}>
            {planOptions.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </Dropdown>
        </ControlField>

        {OFFSET_RUNTIME_FAULTS.has(draft.faultKind) ? (
          <ControlField label="Offset">
            <Input value={draft.value} onChange={(event) => onChange({ value: event.target.value })} />
          </ControlField>
        ) : null}

        {draft.faultKind === "latch_al_error" ? (
          <ControlField label="AL error code">
            <Input value={draft.alErrorCode} onChange={(event) => onChange({ alErrorCode: event.target.value })} />
          </ControlField>
        ) : null}

        {["mailbox_abort", "mailbox_protocol_fault"].includes(draft.faultKind) ? (
          <ControlField label="Mailbox index">
            <Input value={draft.mailboxIndex} onChange={(event) => onChange({ mailboxIndex: event.target.value })} />
          </ControlField>
        ) : null}

        {["mailbox_abort", "mailbox_protocol_fault"].includes(draft.faultKind) ? (
          <ControlField label="Subindex">
            <Input value={draft.mailboxSubindex} onChange={(event) => onChange({ mailboxSubindex: event.target.value })} />
          </ControlField>
        ) : null}

        {draft.faultKind === "mailbox_abort" ? (
          <ControlField label="Abort code">
            <Input value={draft.mailboxAbortCode} onChange={(event) => onChange({ mailboxAbortCode: event.target.value })} />
          </ControlField>
        ) : null}

        {draft.faultKind === "mailbox_abort" ? (
          <ControlField label="Abort stage">
            <Dropdown value={draft.mailboxAbortStage} onChange={(event) => onChange({ mailboxAbortStage: event.target.value })}>
              {MAILBOX_ABORT_STAGES.map((stage) => (
                <option key={stage || "any"} value={stage}>
                  {stage || "any"}
                </option>
              ))}
            </Dropdown>
          </ControlField>
        ) : null}

        {draft.faultKind === "mailbox_protocol_fault" ? (
          <ControlField label="Mailbox stage">
            <Dropdown value={draft.mailboxStage} onChange={(event) => onChange({ mailboxStage: event.target.value })}>
              {MAILBOX_STAGES.map((stage) => (
                <option key={stage} value={stage}>
                  {stage}
                </option>
              ))}
            </Dropdown>
          </ControlField>
        ) : null}

        {draft.faultKind === "mailbox_protocol_fault" ? (
          <ControlField label="Protocol fault">
            <Dropdown value={draft.mailboxFaultKind} onChange={(event) => onChange({ mailboxFaultKind: event.target.value })}>
              {MAILBOX_PROTOCOL_FAULTS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </Dropdown>
          </ControlField>
        ) : null}

        {draft.faultKind === "mailbox_protocol_fault" && MAILBOX_VALUE_FAULTS.has(draft.mailboxFaultKind) ? (
          <ControlField label="Protocol value">
            <Input value={draft.mailboxFaultValue} onChange={(event) => onChange({ mailboxFaultValue: event.target.value })} />
          </ControlField>
        ) : null}

        {draft.plan === "count" ? (
          <ControlField label="Count">
            <Input value={draft.count} onChange={(event) => onChange({ count: event.target.value })} />
          </ControlField>
        ) : null}

        {draft.plan === "after_ms" ? (
          <ControlField label="Delay ms">
            <Input value={draft.delayMs} onChange={(event) => onChange({ delayMs: event.target.value })} />
          </ControlField>
        ) : null}

        {draft.plan === "after_milestone" ? (
          <ControlField label="Milestone">
            <Dropdown value={draft.milestoneKind} onChange={(event) => onChange({ milestoneKind: event.target.value })}>
              {SLAVE_MILESTONE_KINDS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </Dropdown>
          </ControlField>
        ) : null}

        {draft.plan === "after_milestone" ? (
          <ControlField label="Milestone count">
            <Input value={draft.milestoneCount} onChange={(event) => onChange({ milestoneCount: event.target.value })} />
          </ControlField>
        ) : null}

        {draft.plan === "after_milestone" && draft.milestoneKind === "mailbox_step" ? (
          <ControlField label="Milestone stage">
            <Dropdown value={draft.milestoneStage} onChange={(event) => onChange({ milestoneStage: event.target.value })}>
              {MAILBOX_STAGES.map((stage) => (
                <option key={stage} value={stage}>
                  {stage}
                </option>
              ))}
            </Dropdown>
          </ControlField>
        ) : null}
      </Columns>

      {draft.plan === "after_milestone" && draft.milestoneKind !== "healthy_exchanges" ? (
        <MessageLine tone="info">Milestone slave: {selectedSlave || "none selected"}</MessageLine>
      ) : null}
    </Stack>
  );
}

function BusFaultEditor({ draft, onChange }) {
  const planOptions = runtimePlanOptions(draft.faultKind);

  return (
    <Columns minWidth="12rem">
      <ControlField label="Fault">
        <Dropdown value={draft.faultKind} onChange={(event) => onChange({ faultKind: event.target.value })}>
          {BUS_RUNTIME_FAULTS.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </Dropdown>
      </ControlField>

      <ControlField label="Plan">
        <Dropdown value={draft.plan} onChange={(event) => onChange({ plan: event.target.value })}>
          {planOptions.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </Dropdown>
      </ControlField>

      {draft.faultKind === "command_wkc_offset" ? (
        <ControlField label="Command">
          <Dropdown value={draft.command} onChange={(event) => onChange({ command: event.target.value })}>
            {EXCHANGE_COMMANDS.map((command) => (
              <option key={command} value={command}>
                {command}
              </option>
            ))}
          </Dropdown>
        </ControlField>
      ) : null}

      {OFFSET_RUNTIME_FAULTS.has(draft.faultKind) ? (
        <ControlField label="Offset">
          <Input value={draft.value} onChange={(event) => onChange({ value: event.target.value })} />
        </ControlField>
      ) : null}

      {draft.plan === "count" ? (
        <ControlField label="Count">
          <Input value={draft.count} onChange={(event) => onChange({ count: event.target.value })} />
        </ControlField>
      ) : null}

      {draft.plan === "after_ms" ? (
        <ControlField label="Delay ms">
          <Input value={draft.delayMs} onChange={(event) => onChange({ delayMs: event.target.value })} />
        </ControlField>
      ) : null}

      {draft.plan === "after_milestone" ? (
        <ControlField label="Healthy exchanges">
          <Input value={draft.milestoneCount} onChange={(event) => onChange({ milestoneCount: event.target.value })} />
        </ControlField>
      ) : null}
    </Columns>
  );
}

function TransportFaultEditor({ transportFaults, draft, onChange }) {
  if (!transportFaults.enabled) {
    return <EmptyState>Transport edge fault injection is unavailable for this simulator.</EmptyState>;
  }

  if (transportFaults.transport === "raw") {
    const mode = transportFaults.mode ?? "single";

    return (
      <Stack compact>
        <Columns minWidth="12rem">
          <ControlField label="Delay ms">
            <Input value={draft.delayMs} onChange={(event) => onChange({ delayMs: event.target.value })} />
          </ControlField>

          {mode === "redundant" ? (
            <ControlField label="Endpoint">
              <Dropdown value={draft.endpoint} onChange={(event) => onChange({ endpoint: event.target.value })}>
                {rawEndpointOptions(mode).map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </Dropdown>
            </ControlField>
          ) : null}

          <ControlField label="Ingress filter">
            <Dropdown value={draft.fromIngress} onChange={(event) => onChange({ fromIngress: event.target.value })}>
              {rawIngressOptions(mode).map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </Dropdown>
          </ControlField>
        </Columns>

        {mode === "single" ? (
          <MessageLine tone="info">Single raw mode only exposes the primary endpoint.</MessageLine>
        ) : null}
      </Stack>
    );
  }

  return (
    <Columns minWidth="12rem">
      <ControlField label="Reply fault">
        <Dropdown value={draft.mode} onChange={(event) => onChange({ mode: event.target.value })}>
          {UDP_MODES.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </Dropdown>
      </ControlField>

      <ControlField label="Plan">
        <Dropdown value={draft.plan} onChange={(event) => onChange({ plan: event.target.value })}>
          <option value="next">Next reply</option>
          <option value="count">Next N replies</option>
          <option value="script">Script</option>
        </Dropdown>
      </ControlField>

      {draft.plan === "count" ? (
        <ControlField label="Count">
          <Input value={draft.count} onChange={(event) => onChange({ count: event.target.value })} />
        </ControlField>
      ) : null}

      {draft.plan === "script" ? (
        <ControlField label="Script">
          <TextArea rows={4} value={draft.script} onChange={(event) => onChange({ script: event.target.value })} />
        </ControlField>
      ) : null}
    </Columns>
  );
}

function RuntimeLifecycleView({ runtimeFaults, runtimeProperties }) {
  return (
    <Stack compact>
      <SectionCopy>{runtimeFaults.summary ?? "No runtime faults."}</SectionCopy>
      <PropertyList items={runtimeProperties} />

      <Panel title="Sticky runtime faults">
        <Stack compact>
          <SectionCopy>These are active now and stay active until you clear them.</SectionCopy>
          <FaultTable labels={runtimeFaults.sticky_labels} emptyText="No sticky runtime faults are active." />
        </Stack>
      </Panel>

      <Panel title="Queued exchange faults">
        <Stack compact>
          <SectionCopy>These will run on the next exchanges that match your plan.</SectionCopy>
          <FaultTable labels={runtimeFaults.pending_labels} emptyText="No runtime exchange faults are queued." />
        </Stack>
      </Panel>

      <Panel title="Scheduled runtime faults">
        <Stack compact>
          <SectionCopy>These are waiting for a delay or milestone before they become active.</SectionCopy>
          <ScheduledFaultTable faults={runtimeFaults.scheduled_faults} />
        </Stack>
      </Panel>
    </Stack>
  );
}

function TransportLifecycleView({ transportFaults, transportProperties }) {
  return (
    <Stack compact>
      <SectionCopy>{transportFaults.summary ?? "No transport faults."}</SectionCopy>
      <PropertyList items={transportProperties} />

      {transportFaults.transport === "raw" ? (
        <Panel title="Raw endpoint delays">
          <Stack compact>
            <SectionCopy>These transport-edge delays apply before the simulator sends raw responses.</SectionCopy>
            <RawTransportTable endpoints={transportFaults.endpoints} />
          </Stack>
        </Panel>
      ) : (
        <Panel title="Queued transport faults">
          <Stack compact>
            <SectionCopy>These affect future UDP replies without changing simulator state directly.</SectionCopy>
            <FaultTable labels={transportFaults.pending_labels} emptyText="No queued transport faults are active." />
          </Stack>
        </Panel>
      )}
    </Stack>
  );
}

function QuickTransportDrill({ transportFaults, disabled, pushAction }) {
  if (!transportFaults.enabled) {
    return null;
  }

  if (transportFaults.transport === "raw") {
    return (
      <DrillGroup
        title="Transport edge"
        copy="These operate below the simulator core. Raw transport faults delay responses at the endpoint boundary without changing slave state."
        watch={[
          "Task Manager -> Fault summary shows transport-edge delays.",
          "Bus behavior changes without a slave AL state fault.",
        ]}
      >
        <InlineButtons>
          <Button
            disabled={disabled}
            onClick={() =>
              pushAction("apply_transport_fault", {
                transport: "raw",
                kind: "delay_response",
                delay_ms: "75",
                endpoint: transportFaults.mode === "redundant" ? "all" : "primary",
                from_ingress: "all",
              })
            }
          >
            Delay raw responses 75 ms
          </Button>
          {transportFaults.mode === "redundant" ? (
            <Button
              disabled={disabled}
              onClick={() =>
                pushAction("apply_transport_fault", {
                  transport: "raw",
                  kind: "delay_response",
                  delay_ms: "75",
                  endpoint: "secondary",
                  from_ingress: "primary",
                })
              }
            >
              Delay secondary from primary
            </Button>
          ) : null}
        </InlineButtons>
      </DrillGroup>
    );
  }

  return (
    <DrillGroup
      title="Transport edge"
      copy="Only disturb the UDP reply path. The simulator state itself stays healthy."
      watch={[
        "Task Manager -> Runtime shows transport misses instead of slave faults.",
        "Task Manager -> Bus shows reply anomalies and queue activity.",
      ]}
    >
      <InlineButtons>
        <Button
          disabled={disabled}
          onClick={() =>
            pushAction("apply_transport_fault", {
              transport: "udp",
              mode: "truncate",
              plan: "next",
            })
          }
        >
          Truncate next reply
        </Button>
        <Button
          disabled={disabled}
          onClick={() =>
            pushAction("apply_transport_fault", {
              transport: "udp",
              mode: "wrong_idx",
              plan: "count",
              count: "3",
            })
          }
        >
          Wrong index for 3 replies
        </Button>
        <Button
          disabled={disabled}
          onClick={() =>
            pushAction("apply_transport_fault", {
              transport: "udp",
              mode: "replay_previous",
              plan: "next",
            })
          }
        >
          Replay previous reply
        </Button>
      </InlineButtons>
    </DrillGroup>
  );
}

function FaultInjectorSection({ title, copy, editor, validation, action, snippet, disabled, buttonLabel, onApply }) {
  return (
    <Panel title={title}>
      <Stack compact>
        <SectionCopy>{copy}</SectionCopy>
        {editor}
        <ValidationMessages validation={validation} />

        <InlineButtons>
          <Button disabled={disabled || validation.errors.length > 0 || !action} onClick={onApply}>
            {buttonLabel}
          </Button>
        </InlineButtons>

        <Panel title="Action preview">
          <ActionPreview action={action} />
        </Panel>

        <Panel title="Elixir equivalent">
          <Stack compact>
            <SectionCopy>
              This is the direct code form for the current injector state. Copy it into a notebook cell when the fault should become part of a larger text scenario.
            </SectionCopy>
            <CodeBlock code={snippet} />
          </Stack>
        </Panel>
      </Stack>
    </Panel>
  );
}

function SimulatorFaultsPanel({ ctx, data }) {
  const [snapshot, setSnapshot] = useState(data);
  const [selectedSlave, setSelectedSlave] = useState(data.slave_options?.[0] ?? "");
  const [slaveDraft, setSlaveDraft] = useState(() => normalizeSlaveDraft(runtimeDraftDefaults(data.slave_options?.[0] ?? ""), data.slave_options?.[0] ?? ""));
  const [busDraft, setBusDraft] = useState(() => normalizeBusDraft(runtimeDraftDefaults("")));
  const [transportDraft, setTransportDraft] = useState(() =>
    normalizeTransportDraft(transportDraftDefaults(data.transport_faults ?? offlineTransportFaults()), data.transport_faults ?? offlineTransportFaults())
  );

  useEffect(() => {
    ctx.handleEvent("snapshot", (next) => {
      startTransition(() => setSnapshot(next));
    });
  }, [ctx]);

  const slaveOptions = snapshot.slave_options ?? [];
  const slaveOptionsKey = useMemo(() => slaveOptions.join("|"), [slaveOptions]);
  const transportFaults = snapshot.transport_faults ?? offlineTransportFaults();
  const transportSignature = `${transportFaults.transport}:${transportFaults.mode ?? "none"}`;

  useEffect(() => {
    setSelectedSlave((current) => chooseOption(current, slaveOptions));
  }, [slaveOptionsKey]);

  useEffect(() => {
    setSlaveDraft((current) => normalizeSlaveDraft(current, selectedSlave));
  }, [selectedSlave]);

  useEffect(() => {
    setTransportDraft((current) => normalizeTransportDraft(current, transportFaults));
  }, [transportSignature]);

  const disabled = snapshot.status !== "running";
  const runtimeFaults = snapshot.runtime_faults ?? {};
  const transportDisabled = disabled || !transportFaults.enabled;
  const status = <StatusBadge tone={statusTone(snapshot.status)}>{snapshot.status}</StatusBadge>;
  const selectedSlaveDisabled = disabled || !selectedSlave;
  const pushAction = (id, params = {}) => ctx.pushEvent("action", { id, ...params });

  const normalizedSlaveDraft = useMemo(
    () => normalizeSlaveDraft(slaveDraft, selectedSlave),
    [slaveDraft, selectedSlave]
  );
  const normalizedBusDraft = useMemo(() => normalizeBusDraft(busDraft), [busDraft]);
  const normalizedTransportDraft = useMemo(
    () => normalizeTransportDraft(transportDraft, transportFaults),
    [transportDraft, transportSignature]
  );

  const slaveValidation = useMemo(
    () => validateSlaveDraft(normalizedSlaveDraft, selectedSlave),
    [normalizedSlaveDraft, selectedSlave]
  );
  const busValidation = useMemo(() => validateBusDraft(normalizedBusDraft), [normalizedBusDraft]);
  const transportValidation = useMemo(
    () => validateTransportDraft(normalizedTransportDraft, transportFaults),
    [normalizedTransportDraft, transportSignature]
  );

  const slaveAction = useMemo(() => buildRuntimeAction(normalizedSlaveDraft), [normalizedSlaveDraft]);
  const busAction = useMemo(() => buildRuntimeAction(normalizedBusDraft), [normalizedBusDraft]);
  const transportAction = useMemo(
    () => buildTransportAction(normalizedTransportDraft, transportFaults),
    [normalizedTransportDraft, transportSignature]
  );

  const slaveSnippet = useMemo(
    () => (slaveValidation.errors.length ? null : buildRuntimeSnippet(normalizedSlaveDraft)),
    [normalizedSlaveDraft, slaveValidation.errors]
  );
  const busSnippet = useMemo(
    () => (busValidation.errors.length ? null : buildRuntimeSnippet(normalizedBusDraft)),
    [normalizedBusDraft, busValidation.errors]
  );
  const transportSnippet = useMemo(
    () => (transportValidation.errors.length ? null : buildTransportSnippet(normalizedTransportDraft, transportFaults)),
    [normalizedTransportDraft, transportSignature, transportValidation.errors]
  );

  const runtimeProperties = [
    { label: "Next exchange", value: runtimeFaults.next_label ?? "none" },
    { label: "Sticky", value: String(runtimeFaults.sticky_count ?? 0) },
    { label: "Queued", value: String(runtimeFaults.pending_count ?? 0) },
    { label: "Scheduled", value: String(runtimeFaults.scheduled_count ?? 0) },
  ];

  const transportProperties =
    transportFaults.transport === "raw"
      ? [
          { label: "Mode", value: transportFaults.mode ?? "single" },
          { label: "Endpoints", value: String((transportFaults.endpoints ?? []).length) },
          { label: "Delayed", value: String(transportFaults.active_count ?? 0) },
        ]
      : [
          { label: "Endpoint", value: transportFaults.endpoint ?? "disabled" },
          { label: "Next reply", value: transportFaults.next_label ?? "none" },
          { label: "Queued replies", value: String(transportFaults.active_count ?? 0) },
          { label: "Captured", value: transportFaults.last_response_captured ? "yes" : "no" },
        ];

  const lifecycleItems = [
    {
      label: "Active now",
      value: (
        <span>
          <StatusBadge tone={(runtimeFaults.sticky_count ?? 0) > 0 ? "danger" : "neutral"}>
            {String(runtimeFaults.sticky_count ?? 0)}
          </StatusBadge>
        </span>
      ),
    },
    {
      label: "Queued next",
      value: (
        <span>
          <StatusBadge tone={(runtimeFaults.pending_count ?? 0) > 0 ? "warn" : "neutral"}>
            {String(runtimeFaults.pending_count ?? 0)}
          </StatusBadge>
        </span>
      ),
    },
    {
      label: "Scheduled later",
      value: (
        <span>
          <StatusBadge tone={(runtimeFaults.scheduled_count ?? 0) > 0 ? "warn" : "neutral"}>
            {String(runtimeFaults.scheduled_count ?? 0)}
          </StatusBadge>
        </span>
      ),
    },
  ];

  if (transportFaults.enabled) {
    lifecycleItems.push({
      label: "Transport",
      value: (
        <span>
          <StatusBadge tone={(transportFaults.active_count ?? 0) > 0 ? "warn" : "neutral"}>
            {String(transportFaults.active_count ?? 0)}
          </StatusBadge>
        </span>
      ),
    });
  }

  const updateSlaveDraft = (changes) => {
    setSlaveDraft((current) => normalizeSlaveDraft({ ...current, ...changes }, selectedSlave));
  };

  const updateBusDraft = (changes) => {
    setBusDraft((current) => normalizeBusDraft({ ...current, ...changes }));
  };

  const updateTransportDraft = (changes) => {
    setTransportDraft((current) => normalizeTransportDraft({ ...current, ...changes }, transportFaults));
  };

  return (
    <Shell title="Simulator faults" subtitle={snapshot.kind} status={status}>
      <Stack>
        <MessageLine tone={snapshot.message?.level === "error" ? "error" : "info"}>
          {snapshot.message?.text ?? null}
        </MessageLine>

        <SummaryGrid items={snapshot.summary ?? []} />

        <Panel
          title="Quick drills"
          actions={
            <InlineButtons>
              <Button
                disabled={disabled || runtimeFaults.active_count === 0}
                onClick={() => pushAction("clear_runtime_faults")}
              >
                Clear runtime
              </Button>
              {transportFaults.enabled ? (
                <Button
                  disabled={transportDisabled || transportFaults.active_count === 0}
                  onClick={() => pushAction("clear_transport_faults")}
                >
                  Clear transport
                </Button>
              ) : null}
              <Button
                disabled={disabled || (runtimeFaults.active_count === 0 && transportFaults.active_count === 0)}
                onClick={() => pushAction("clear_faults")}
              >
                Clear all
              </Button>
            </InlineButtons>
          }
        >
          <Stack compact>
            <SectionCopy>
              Start here. Each drill teaches one recovery pattern without forcing you to build a whole scenario in the UI.
            </SectionCopy>

            <DrillGroup
              title="Cycle recovery"
              copy="Disturb the exchange itself without targeting a specific slave first."
              watch={[
                "Task Manager -> Runtime shows invalid cycles or WKC mismatches.",
                "Task Manager -> Events shows the recovery start and recovery success.",
              ]}
            >
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
              </InlineButtons>
            </DrillGroup>

            <DrillGroup
              title="Slave recovery"
              copy="Use these when you want one slave to fall out of the healthy path."
              watch={[
                "Task Manager -> Slaves shows one device leaving OP.",
                "Task Manager -> Overview shows the master entering recovery.",
              ]}
            >
              <ControlField label="Target slave">
                <Dropdown
                  disabled={!slaveOptions.length}
                  value={selectedSlave}
                  onChange={(event) => setSelectedSlave(event.target.value)}
                >
                  {slaveOptions.map((name) => (
                    <option key={name} value={name}>
                      {name}
                    </option>
                  ))}
                </Dropdown>
              </ControlField>

              <InlineButtons>
                <Button disabled={selectedSlaveDisabled} onClick={() => pushAction("inject_disconnect", { slave: selectedSlave })}>
                  Disconnect slave
                </Button>
                <Button disabled={selectedSlaveDisabled} onClick={() => pushAction("retreat_to_safeop", { slave: selectedSlave })}>
                  Send slave to SAFEOP
                </Button>
              </InlineButtons>
            </DrillGroup>

            <QuickTransportDrill transportFaults={transportFaults} disabled={transportDisabled} pushAction={pushAction} />
          </Stack>
        </Panel>

        <Panel title="Fault injector">
          <Stack compact>
            <SectionCopy>
              Work top to bottom. Use <Mono>Single slave</Mono> when you want to break one device, and <Mono>Bus</Mono> when you want exchange-level or transport-edge faults.
            </SectionCopy>

            <FaultInjectorSection
              title="Single slave"
              copy="Pick one slave once, then inject state, mailbox, or slave-scoped exchange faults against that target."
              editor={
                <SlaveFaultEditor
                  selectedSlave={selectedSlave}
                  slaveOptions={slaveOptions}
                  draft={normalizedSlaveDraft}
                  onSelectSlave={setSelectedSlave}
                  onChange={updateSlaveDraft}
                />
              }
              validation={slaveValidation}
              action={slaveAction}
              snippet={slaveSnippet}
              disabled={selectedSlaveDisabled}
              buttonLabel={normalizedSlaveDraft.plan === "immediate" ? "Apply slave fault" : "Queue slave fault"}
              onApply={() => pushAction(slaveAction.id, slaveAction.params)}
            />

            <Panel title="Bus">
              <Stack compact>
                <SectionCopy>
                  Bus faults are transport-independent exchange faults plus transport-edge faults for the currently active simulator transport.
                </SectionCopy>

                <FaultInjectorSection
                  title="Exchange faults"
                  copy="Use these for bus-wide exchange failures without selecting a specific slave."
                  editor={<BusFaultEditor draft={normalizedBusDraft} onChange={updateBusDraft} />}
                  validation={busValidation}
                  action={busAction}
                  snippet={busSnippet}
                  disabled={disabled}
                  buttonLabel={normalizedBusDraft.plan === "immediate" ? "Apply bus fault" : "Queue bus fault"}
                  onApply={() => pushAction(busAction.id, busAction.params)}
                />

                {transportFaults.enabled ? (
                  <FaultInjectorSection
                    title={transportFaults.transport === "raw" ? "Transport edge (raw)" : "Transport edge (UDP)"}
                    copy={
                      transportFaults.transport === "raw"
                        ? "Raw transport faults live at the endpoint boundary. In redundant mode they can target primary and secondary endpoints independently."
                        : "UDP transport faults corrupt or replay replies before they reach the master."
                    }
                    editor={<TransportFaultEditor transportFaults={transportFaults} draft={normalizedTransportDraft} onChange={updateTransportDraft} />}
                    validation={transportValidation}
                    action={transportAction}
                    snippet={transportSnippet}
                    disabled={transportDisabled}
                    buttonLabel="Apply transport fault"
                    onApply={() => pushAction(transportAction.id, transportAction.params)}
                  />
                ) : (
                  <MessageLine tone="info">This simulator is not exposing a transport-edge fault surface.</MessageLine>
                )}
              </Stack>
            </Panel>
          </Stack>
        </Panel>

        <Panel title="Fault lifecycle">
          <Stack compact>
            <SectionCopy>
              Read this left to right: active now, queued for the next exchanges, then delayed for later.
            </SectionCopy>

            <SummaryGrid items={lifecycleItems} />

            {transportFaults.enabled ? (
              <Tabs defaultActiveTab="Runtime">
                <Tab title="Runtime">
                  <RuntimeLifecycleView runtimeFaults={runtimeFaults} runtimeProperties={runtimeProperties} />
                </Tab>

                <Tab title="Transport">
                  <TransportLifecycleView transportFaults={transportFaults} transportProperties={transportProperties} />
                </Tab>
              </Tabs>
            ) : (
              <RuntimeLifecycleView runtimeFaults={runtimeFaults} runtimeProperties={runtimeProperties} />
            )}
          </Stack>
        </Panel>
      </Stack>
    </Shell>
  );
}
