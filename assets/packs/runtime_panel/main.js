import "./main.css";

import React, { startTransition, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

import {
  Button,
  ControlField,
  DataTable,
  Dropdown,
  EmptyState,
  Frame,
  InlineButtons,
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
  root.render(<RuntimePanel ctx={ctx} data={data} />);
}

const MESSAGE_TONES = {
  info: "info",
  error: "error",
};

function statusTone(status) {
  const value = String(status ?? "").toLowerCase();

  if (["operational", "ok", "op", "locked", "active", "preop_ready"].includes(value)) {
    return "ok";
  }

  if (
    ["unavailable", "error", "fault", "activation_blocked", "down"].includes(value) ||
    value.includes("error")
  ) {
    return "danger";
  }

  if (["recovering", "awaiting_preop", "discovering", "safeop", "preop", "inactive"].includes(value)) {
    return "warn";
  }

  return "neutral";
}

function RuntimePanel({ ctx, data }) {
  const [snapshot, setSnapshot] = useState(data);

  useEffect(() => {
    ctx.handleEvent("snapshot", (next) => {
      startTransition(() => setSnapshot(next));
    });
  }, [ctx]);

  const status = <StatusBadge tone={statusTone(snapshot.status)}>{snapshot.status}</StatusBadge>;

  return (
    <Shell
      title={snapshot.title}
      subtitle={snapshot.kind}
      status={status}
    >
      <MessageLine tone={MESSAGE_TONES[snapshot.message?.level] ?? "info"}>
        {snapshot.message?.text ?? null}
      </MessageLine>

      <SummaryGrid items={snapshot.summary} />

      <div className="ke95-grid ke95-grid--2">
        <Panel title="Controls">
          <Controls ctx={ctx} controls={snapshot.controls} />
        </Panel>

        {snapshot.details.length > 0 ? (
          <Panel title="Details">
            <Details items={snapshot.details} />
          </Panel>
        ) : (
          <EmptyState>No extra detail fields for this resource.</EmptyState>
        )}
      </div>

      {snapshot.tables.map((table) => (
        <Panel key={table.title} title={table.title}>
          <TableSection table={table} />
        </Panel>
      ))}
    </Shell>
  );
}

function Controls({ ctx, controls }) {
  const [inputValue, setInputValue] = useState(controls?.input?.value ?? "");
  const [selectValue, setSelectValue] = useState(controls?.select?.options?.[0] ?? "");

  useEffect(() => {
    setInputValue(controls?.input?.value ?? "");
    setSelectValue(controls?.select?.options?.[0] ?? "");
  }, [controls]);

  if (!controls) {
    return <EmptyState>No runtime controls available.</EmptyState>;
  }

  return (
    <div className="ke95-grid">
      {controls.buttons?.length > 0 ? (
        <InlineButtons>
          {controls.buttons.map((button) => (
            <Button key={button.id} onClick={() => ctx.pushEvent("action", { id: button.id })}>
              {button.label}
            </Button>
          ))}
        </InlineButtons>
      ) : null}

      {controls.select ? (
        <div className="ke95-toolbar">
          <ControlField label={controls.select.label} className="ke95-fill">
            <Dropdown
              value={selectValue}
              className="ke95-fill"
              onChange={(event) => setSelectValue(event.target.value)}
            >
              {controls.select.options.map((option) => (
                <option key={option} value={option}>
                  {option}
                </option>
              ))}
            </Dropdown>
          </ControlField>
          <Button onClick={() => ctx.pushEvent("action", { id: controls.select.id, value: selectValue })}>
            Apply
          </Button>
        </div>
      ) : null}

      {controls.input ? (
        <div className="ke95-toolbar">
          <ControlField label={controls.input.label} className="ke95-fill">
            <Input
              value={inputValue}
              className="ke95-fill"
              onChange={(event) => setInputValue(event.target.value)}
            />
          </ControlField>
          <Button
            onClick={() =>
              ctx.pushEvent("action", {
                id: controls.submit?.id ?? controls.input.id,
                value: inputValue,
              })
            }
          >
            {controls.submit?.label ?? "Apply"}
          </Button>
        </div>
      ) : null}
    </div>
  );
}

function Details({ items }) {
  return (
    <div className="ke95-detail-grid">
      {items.map((item) => (
        <Frame key={item.label} boxShadow="in" className="ke95-summary__item ke95-detail">
          <div className="ke95-summary__label">{item.label}</div>
          <Mono as="div" className="ke95-detail__value">
            {item.value}
          </Mono>
        </Frame>
      ))}
    </div>
  );
}

function TableSection({ table }) {
  if (!table.rows.length) {
    return <EmptyState>No rows available.</EmptyState>;
  }

  return (
    <DataTable headers={table.headers}>
      {table.rows.map((row) => (
        <tr key={row.key}>
          {row.cells.map((cell, index) => (
            <td key={`${row.key}-${index}`}>
              <Mono>{cell}</Mono>
            </td>
          ))}
        </tr>
      ))}
    </DataTable>
  );
}
