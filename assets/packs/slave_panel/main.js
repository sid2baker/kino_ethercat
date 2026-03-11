import "./main.css";

import React, { startTransition, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

import {
  Button,
  Columns,
  EmptyState,
  Inset,
  InlineButtons,
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
  root.render(<SlavePanel ctx={ctx} initialData={data} />);
}

function toneFromStatus(value) {
  if (["live", "op", "cycling"].includes(value)) return "ok";
  if (["stale", "safeop", "preop", "open"].includes(value)) return "warn";
  if (["unavailable", "stopped"].includes(value)) return "danger";
  return "neutral";
}

function toHex(value, pad = 4) {
  if (value == null) return "n/a";
  return "0x" + (value >>> 0).toString(16).toUpperCase().padStart(pad, "0");
}

function SlavePanel({ ctx, initialData }) {
  const [data, setData] = useState(initialData);

  useEffect(() => {
    ctx.handleEvent("snapshot", (nextData) => {
      startTransition(() => setData(nextData));
    });
  }, [ctx]);

  if (!data) return null;

  const headerStatus = (
    <>
      <StatusBadge tone={toneFromStatus(data.status)}>{data.status}</StatusBadge>
      <StatusBadge tone={toneFromStatus(data.summary.al_state)}>{data.summary.al_state}</StatusBadge>
      {data.summary.coe === true ? <StatusBadge tone="neutral">CoE</StatusBadge> : null}
    </>
  );

  return (
    <Shell
      title={data.summary.name}
      subtitle={data.runtime_error || data.summary.driver || "slave panel"}
      status={headerStatus}
    >
      {data.status === "unavailable" ? (
        <EmptyState>Start the master and this panel will attach automatically.</EmptyState>
      ) : (
        <Stack className="ke95-slave-panel">
          {data.write_error ? (
            <MessageLine tone="error">
              write {data.write_error.signal}: {data.write_error.reason}
            </MessageLine>
          ) : null}

          <SummaryGrid
            items={[
              { label: "Station", value: toHex(data.summary.station) },
              { label: "Driver", value: data.summary.driver || "n/a" },
              { label: "Config", value: data.summary.configuration_error || "ok" },
              { label: "Inputs", value: String(data.inputs.length) },
              { label: "Outputs", value: String(data.outputs.length) },
              { label: "Runtime", value: data.runtime_error || "ok" },
            ]}
          />

          {data.domains.length > 0 ? (
            <Panel title="Domains">
              <Columns minWidth="11rem">
                {data.domains.map((domain) => (
                  <Inset key={domain.id} className="ke95-slave-panel__domain">
                    <div className="ke95-toolbar">
                      <Mono>{domain.id}</Mono>
                      <StatusBadge tone={toneFromStatus(domain.state)}>{domain.state}</StatusBadge>
                    </div>
                    <Mono as="div">miss {domain.miss_count}</Mono>
                    <Mono as="div">total {domain.total_miss_count}</Mono>
                    <Mono as="div">wkc {domain.expected_wkc}</Mono>
                  </Inset>
                ))}
              </Columns>
            </Panel>
          ) : null}

          {data.summary.identity ? (
            <Panel title="Identity">
              <PropertyList
                minWidth="11rem"
                items={[
                  { label: "Vendor", value: toHex(data.summary.identity.vendor_id, 8) },
                  { label: "Product", value: toHex(data.summary.identity.product_code, 8) },
                  { label: "Revision", value: toHex(data.summary.identity.revision, 8) },
                  { label: "Serial", value: toHex(data.summary.identity.serial_number, 8) },
                ]}
              />
            </Panel>
          ) : null}

          <SignalSection title="Inputs" signals={data.inputs} ctx={ctx} />
          <SignalSection title="Outputs" signals={data.outputs} ctx={ctx} />
        </Stack>
      )}
    </Shell>
  );
}

function SignalSection({ title, signals, ctx }) {
  return (
    <Panel title={title}>
      {signals.length === 0 ? (
        <EmptyState>No signals</EmptyState>
      ) : (
        <Stack compact>
          {signals.map((signal) => (
            <SignalCard key={`${signal.direction}:${signal.name}`} signal={signal} ctx={ctx} />
          ))}
        </Stack>
      )}
    </Panel>
  );
}

function SignalCard({ signal, ctx }) {
  const activeTone = signal.known ? (signal.active ? "ok" : "neutral") : "warn";

  return (
    <Inset className="ke95-slave-panel__signal">
      <div className="ke95-toolbar">
        <Stack compact>
          <Mono>{signal.name}</Mono>
          <Mono>{signal.domain} • {signal.bit_size} bit</Mono>
        </Stack>
        {signal.kind === "bit" ? <StatusBadge tone={activeTone}>{signal.display}</StatusBadge> : null}
      </div>

      <Mono as="div">{signal.display}</Mono>
      {signal.updated_at ? <Mono as="div">updated {signal.updated_at}</Mono> : null}

      {signal.writable ? (
        <InlineButtons>
          <Button onClick={() => ctx.pushEvent("set_output", { signal: signal.name, value: 0 })}>Off</Button>
          <Button onClick={() => ctx.pushEvent("set_output", { signal: signal.name, value: 1 })}>On</Button>
        </InlineButtons>
      ) : signal.direction === "output" ? (
        <Mono as="div">Write this signal manually in the notebook.</Mono>
      ) : null}
    </Inset>
  );
}
