import "./main.css";

import React, { startTransition, useEffect } from "react";
import { createRoot } from "react-dom/client";

import {
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

function IntroductionPanel({ ctx, data }) {
  const [snapshot, setSnapshot] = React.useState(data);
  const status = <StatusBadge tone={statusTone(snapshot.status)}>{snapshot.status}</StatusBadge>;

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
