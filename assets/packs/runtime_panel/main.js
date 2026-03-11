import "./main.css";

import React, { startTransition, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

import {
  Button,
  Columns,
  ControlField,
  DataTable,
  Dropdown,
  EmptyState,
  Inset,
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

export async function init(ctx, data) {
  await ctx.importCSS("main.css");
  const root = createRoot(ctx.root);
  root.render(<RuntimePanel ctx={ctx} data={data} />);
}

const MESSAGE_TONES = {
  info: "info",
  error: "error",
};

const LOG_TONES = {
  debug: "neutral",
  info: "neutral",
  notice: "ok",
  warning: "warn",
  error: "danger",
  critical: "danger",
  alert: "danger",
  emergency: "danger",
};

function statusTone(status) {
  const value = String(status ?? "").toLowerCase();

  if (["operational", "ok", "op", "locked", "active"].includes(value)) {
    return "ok";
  }

  if (
    ["unavailable", "error", "fault", "activation_blocked", "down"].includes(value) ||
    value.includes("error")
  ) {
    return "danger";
  }

  if (
    ["recovering", "awaiting_preop", "discovering", "preop_ready", "deactivated", "safeop", "preop", "inactive"].includes(
      value
    )
  ) {
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
      {({ fullscreenActive }) => (
        <Stack className={`ke95-runtime-panel${fullscreenActive ? " ke95-runtime-panel--fullscreen" : ""}`}>
          <MessageLine tone={MESSAGE_TONES[snapshot.message?.level] ?? "info"}>
            {snapshot.message?.text ?? null}
          </MessageLine>

          <SummaryGrid items={snapshot.summary} />

          {snapshot.controls ? (
            <Panel title={snapshot.controls?.title ?? "Controls"} className="ke95-runtime-panel__controls">
              <Controls ctx={ctx} controls={snapshot.controls} />
            </Panel>
          ) : null}

          {snapshot.details.length > 0 ? (
            <Panel title={snapshot.details_title ?? "Details"} className="ke95-runtime-panel__details">
              <Details items={snapshot.details} />
            </Panel>
          ) : null}

          {snapshot.tables.map((table) => (
            <Panel key={table.title} title={table.title} className="ke95-runtime-panel__table">
              <TableSection table={table} />
            </Panel>
          ))}

          <Panel title="Logs" className="ke95-runtime-panel__logs">
            <LogSection ctx={ctx} logs={snapshot.logs ?? []} controls={snapshot.log_controls} />
          </Panel>
        </Stack>
      )}
    </Shell>
  );
}

function Controls({ ctx, controls }) {
  const [inputValue, setInputValue] = useState(controls?.input?.value ?? "");
  const [selectValue, setSelectValue] = useState(selectControlValue(controls?.select));

  useEffect(() => {
    setInputValue(controls?.input?.value ?? "");
  }, [controls?.input?.id, controls?.input?.value]);

  useEffect(() => {
    setSelectValue(selectControlValue(controls?.select));
  }, [controls?.select?.id, controls?.select?.value, selectControlOptionsKey(controls?.select)]);

  if (!controls) {
    return <EmptyState>No runtime controls available.</EmptyState>;
  }

  return (
    <Stack compact>
      {controls.buttons?.length > 0 ? (
        <InlineButtons>
          {controls.buttons.map((button) => (
            <Button
              key={button.id}
              disabled={button.disabled}
              title={button.title}
              onClick={() => ctx.pushEvent("action", { id: button.id })}
            >
              {button.label}
            </Button>
          ))}
        </InlineButtons>
      ) : null}

      {controls.select ? (
        <SelectControl
          control={controls.select}
          value={selectValue}
          onChange={setSelectValue}
          onApply={(value) => ctx.pushEvent("action", { id: controls.select.id, value })}
        />
      ) : null}

      {controls.input ? (
        <Columns minWidth="14rem" className="ke95-runtime-panel__input-row">
          <ControlField label={controls.input.label} className="ke95-fill">
            <Input
              value={inputValue}
              className="ke95-fill"
              onChange={(event) => setInputValue(event.target.value)}
            />
          </ControlField>
          <InlineButtons className="ke95-runtime-panel__input-actions">
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
          </InlineButtons>
        </Columns>
      ) : null}

      {controls.summary?.length > 0 ? <SummaryGrid items={controls.summary} /> : null}
      {controls.help ? <MessageLine tone="info">{controls.help}</MessageLine> : null}
    </Stack>
  );
}

function SelectControl({ control, value, onChange, onApply }) {
  return (
    <div className="ke95-toolbar">
      <ControlField label={control.label} className="ke95-fill">
        <Dropdown value={value} className="ke95-fill" onChange={(event) => onChange(event.target.value)}>
          {control.options.map((option) => (
            <option key={option} value={option}>
              {option}
            </option>
          ))}
        </Dropdown>
      </ControlField>
      <Button onClick={() => onApply(value)}>Apply</Button>
    </div>
  );
}

function selectControlValue(control) {
  return control?.value ?? control?.options?.[0] ?? "";
}

function selectControlOptionsKey(control) {
  return (control?.options ?? []).join("|");
}

function Details({ items }) {
  return <PropertyList items={items} className="ke95-runtime-panel__properties" minWidth="11rem" />;
}

function LogSection({ ctx, logs, controls }) {
  const [logSelectValue, setLogSelectValue] = useState(selectControlValue(controls?.select));
  const [searchValue, setSearchValue] = useState("");

  useEffect(() => {
    setLogSelectValue(selectControlValue(controls?.select));
  }, [controls?.select?.id, controls?.select?.value, selectControlOptionsKey(controls?.select)]);

  const filteredLogs = filterLogs(logs, searchValue);

  return (
    <Stack compact>
      {controls ? (
        <div className="ke95-runtime-log__toolbar">
          {controls.select ? (
            <div className="ke95-runtime-log__filter">
              <ControlField label={controls.select.label} className="ke95-fill">
                <Dropdown
                  value={logSelectValue}
                  className="ke95-fill"
                  onChange={(event) => {
                    const value = event.target.value;
                    setLogSelectValue(value);
                    ctx.pushEvent("action", { id: controls.select.id, value });
                  }}
                >
                  {controls.select.options.map((option) => (
                    <option key={option} value={option}>
                      {option}
                    </option>
                  ))}
                </Dropdown>
              </ControlField>
            </div>
          ) : null}
          <ControlField label="Search" className="ke95-runtime-log__search">
            <Input className="ke95-fill" value={searchValue} onChange={(event) => setSearchValue(event.target.value)} />
          </ControlField>
          {controls.buttons?.length > 0 ? (
            <InlineButtons className="ke95-runtime-log__actions">
              {controls.buttons.map((button) => (
                <Button
                  key={button.id}
                  disabled={button.disabled}
                  title={button.title}
                  onClick={() => ctx.pushEvent("action", { id: button.id })}
                >
                  {button.label}
                </Button>
              ))}
            </InlineButtons>
          ) : null}
        </div>
      ) : null}

      {filteredLogs.length ? (
        <Inset className="ke95-runtime-log">
          {filteredLogs.map((entry) => (
            <div key={entry.id} className="ke95-runtime-log__row">
              <Mono as="div" className="ke95-runtime-log__time">
                {entry.time}
              </Mono>
              <StatusBadge tone={LOG_TONES[entry.level] ?? "neutral"}>{entry.level}</StatusBadge>
              <Mono as="div" className="ke95-runtime-log__message">
                {entry.text}
              </Mono>
            </div>
          ))}
        </Inset>
      ) : logs.length ? (
        <EmptyState>No log entries match the current filters.</EmptyState>
      ) : (
        <EmptyState>No logs captured for this resource yet.</EmptyState>
      )}
    </Stack>
  );
}

function filterLogs(logs, query) {
  const needle = String(query ?? "").trim().toLowerCase();

  if (!needle) {
    return logs;
  }

  return logs.filter((entry) =>
    [entry.time, entry.level, entry.text].some((part) => String(part ?? "").toLowerCase().includes(needle))
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
