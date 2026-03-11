import "./main.css";

import React, { startTransition, useEffect } from "react";
import { createRoot } from "react-dom/client";

import {
  Button,
  DataTable,
  EmptyState,
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
  root.render(<IntroductionPanel ctx={ctx} data={data} />);
}

function statusTone(status) {
  return status === "running" ? "ok" : "neutral";
}

function stepTone(state) {
  if (state === "done") return "ok";
  if (state === "current") return "warn";
  return "neutral";
}

function signalTone(value, on) {
  if (value === "nil") return "neutral";
  return on ? "ok" : "neutral";
}

function IntroductionPanel({ ctx, data }) {
  const [snapshot, setSnapshot] = React.useState(data);
  const status = <StatusBadge tone={statusTone(snapshot.status)}>{snapshot.status}</StatusBadge>;
  const hasWritableRows = (snapshot.playground?.rows ?? []).some((row) => row.writable);

  useEffect(() => {
    ctx.handleEvent("snapshot", (next) => {
      startTransition(() => setSnapshot(next));
    });
  }, [ctx]);

  return (
    <Shell title={snapshot.title} subtitle={snapshot.kind} status={status}>
      <Stack className="ke95-intro-panel">
        <MessageLine tone={snapshot.message?.level === "error" ? "error" : "info"}>
          {snapshot.message?.text ?? null}
        </MessageLine>

        <SummaryGrid items={snapshot.summary ?? []} />

        <Panel title="Use Setup and Master">
          <Stack compact>
            <PropertyList items={snapshot.setup_workflow ?? []} minWidth="14rem" />
          </Stack>
        </Panel>

        <Panel title="Learning path">
          <LearningPath steps={snapshot.path ?? []} />
        </Panel>

        <Panel title="State and health">
          <Stack compact>
            <PropertyList items={snapshot.state_overview ?? []} minWidth="14rem" />
          </Stack>
        </Panel>

        <Panel
          title="Optional loopback playground"
          actions={
            <InlineButtons>
              <Button
                disabled={!hasWritableRows}
                onClick={() => ctx.pushEvent("action", { id: "reset_outputs" })}
              >
                Zero outputs
              </Button>
            </InlineButtons>
          }
        >
          <Stack compact>
            <MessageLine tone="info">{snapshot.playground?.hint ?? null}</MessageLine>
            <PlaygroundTable ctx={ctx} rows={snapshot.playground?.rows ?? []} />
          </Stack>
        </Panel>
      </Stack>
    </Shell>
  );
}

function LearningPath({ steps }) {
  if (!steps.length) {
    return <EmptyState>No guided steps are available yet.</EmptyState>;
  }

  return (
    <div className="ke95-intro-panel__steps">
      {steps.map((step) => (
        <div key={step.title} className="ke95-intro-panel__step">
          <div className="ke95-intro-panel__step-header">
            <Mono className="ke95-intro-panel__step-title">{step.title}</Mono>
            <StatusBadge tone={stepTone(step.state)}>{step.state}</StatusBadge>
          </div>
          <div className="ke95-intro-panel__step-body">{step.body}</div>
        </div>
      ))}
    </div>
  );
}

function PlaygroundTable({ ctx, rows }) {
  if (!rows.length) {
    return <EmptyState>No connected output/input pairs are available yet.</EmptyState>;
  }

  return (
    <DataTable headers={["Connection", "Output", "Input", "Action"]}>
      {rows.map((row) => (
        <tr key={row.key}>
          <td className="ke95-intro-panel__connection">
            <Mono>{`${row.source_slave}.${row.source_signal}`}</Mono>
            <Mono>{`-> ${row.target_slave}.${row.target_signal}`}</Mono>
          </td>
          <td>
            <StatusBadge tone={signalTone(row.source_value, row.source_on)}>{row.source_value}</StatusBadge>
          </td>
          <td>
            <StatusBadge tone={signalTone(row.target_value, row.target_on)}>{row.target_value}</StatusBadge>
          </td>
          <td>
            {row.writable ? (
              <InlineButtons>
                <Button
                  disabled={!row.source_on}
                  onClick={() =>
                    ctx.pushEvent("action", {
                      id: "set_output",
                      slave: row.source_slave,
                      signal: row.source_signal,
                      value: "0",
                    })
                  }
                >
                  Off
                </Button>
                <Button
                  disabled={row.source_on}
                  onClick={() =>
                    ctx.pushEvent("action", {
                      id: "set_output",
                      slave: row.source_slave,
                      signal: row.source_signal,
                      value: "1",
                    })
                  }
                >
                  On
                </Button>
              </InlineButtons>
            ) : (
              <Mono>{row.bit_size > 0 ? `${row.bit_size} bit observed` : "observed"}</Mono>
            )}
          </td>
        </tr>
      ))}
    </DataTable>
  );
}
