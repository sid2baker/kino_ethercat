import "./main.css";

import React, { startTransition, useEffect } from "react";
import { createRoot } from "react-dom/client";

import {
  EmptyState,
  MessageLine,
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
      <Stack>
        <MessageLine tone={snapshot.message?.level === "error" ? "error" : "info"}>
          {snapshot.message?.text ?? null}
        </MessageLine>

        <SummaryGrid items={snapshot.summary ?? []} />

        <Panel title="Phase 1: Mental model">
          <Stack compact>
            <PropertyList items={snapshot.mental_model ?? []} minWidth="14rem" />
          </Stack>
        </Panel>

        <Panel title="Phase 2: First interactive contact">
          <LearningPath steps={snapshot.first_contact ?? []} />
        </Panel>

        <Panel title="Next after phase 2">
          <Stack compact>
            <PropertyList items={snapshot.next_after_intro ?? []} minWidth="14rem" />
          </Stack>
        </Panel>

        <Panel title="Current state and health">
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
    <Stack compact>
      {steps.map((step) => (
        <Panel
          key={step.title}
          title={step.title}
          actions={<StatusBadge tone={stepTone(step.state)}>{step.state}</StatusBadge>}
        >
          {step.body}
        </Panel>
      ))}
    </Stack>
  );
}
