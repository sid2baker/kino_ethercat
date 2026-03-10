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
      {({ fullscreenActive }) => (
        <div className={`ke95-runtime-panel${fullscreenActive ? " ke95-runtime-panel--fullscreen" : ""}`}>
          <MessageLine tone={MESSAGE_TONES[snapshot.message?.level] ?? "info"}>
            {snapshot.message?.text ?? null}
          </MessageLine>

          <SummaryGrid items={snapshot.summary} />

          <div className="ke95-grid ke95-grid--2">
            <Panel title="Controls" className="ke95-runtime-panel__controls">
              <Controls ctx={ctx} controls={snapshot.controls} />
            </Panel>

            {snapshot.details.length > 0 ? (
              <Panel title="Details" className="ke95-runtime-panel__details">
                <Details items={snapshot.details} />
              </Panel>
            ) : (
              <EmptyState>No extra detail fields for this resource.</EmptyState>
            )}
          </div>

          {snapshot.tables.map((table) => (
            <Panel key={table.title} title={table.title} className="ke95-runtime-panel__table">
              <TableSection table={table} />
            </Panel>
          ))}

          <Panel title="Logs" className="ke95-runtime-panel__logs">
            <LogSection ctx={ctx} logs={snapshot.logs ?? []} controls={snapshot.log_controls} />
          </Panel>
        </div>
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
    <div className="ke95-grid">
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

function LogSection({ ctx, logs, controls }) {
  const [logSelectValue, setLogSelectValue] = useState(selectControlValue(controls?.select));
  const [searchValue, setSearchValue] = useState("");

  useEffect(() => {
    setLogSelectValue(selectControlValue(controls?.select));
  }, [controls?.select?.id, controls?.select?.value, selectControlOptionsKey(controls?.select)]);

  const filteredLogs = filterLogs(logs, searchValue);

  return (
    <div className="ke95-grid">
      {controls ? (
        <div className="ke95-runtime-log__toolbar">
          {controls.select ? (
            <div className="ke95-runtime-log__filter">
              <ControlField label={controls.select.label} className="ke95-fill">
                <Dropdown
                  value={logSelectValue}
                  className="ke95-fill"
                  onChange={(event) => setLogSelectValue(event.target.value)}
                >
                  {controls.select.options.map((option) => (
                    <option key={option} value={option}>
                      {option}
                    </option>
                  ))}
                </Dropdown>
              </ControlField>
              <Button onClick={() => ctx.pushEvent("action", { id: controls.select.id, value: logSelectValue })}>
                Apply
              </Button>
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
        <Frame boxShadow="in" className="ke95-runtime-log">
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
        </Frame>
      ) : logs.length ? (
        <EmptyState>No log entries match the current filters.</EmptyState>
      ) : (
        <EmptyState>No logs captured for this resource yet.</EmptyState>
      )}
    </div>
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
