import "./main.css";

import React, { startTransition, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

export async function init(ctx, data) {
  await ctx.importCSS("main.css");
  const root = createRoot(ctx.root);
  root.render(<RuntimePanel ctx={ctx} data={data} />);
}

const BADGE_TONES = {
  ok: "ke-runtime__badge--ok",
  warn: "ke-runtime__badge--warn",
  danger: "ke-runtime__badge--danger",
  neutral: "ke-runtime__badge--neutral",
};

const MESSAGE_TONES = {
  info: "ke-runtime__message--info",
  error: "ke-runtime__message--error",
};

const BUTTON_TONES = {
  primary: "ke-runtime__button--primary",
  secondary: "ke-runtime__button--secondary",
  danger: "ke-runtime__button--danger",
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

  if (["recovering", "awaiting_preop", "discovering", "safeop", "preop"].includes(value)) {
    return "warn";
  }

  return "neutral";
}

function Badge({ label }) {
  return (
    <span className={`ke-runtime__badge ${BADGE_TONES[statusTone(label)]}`}>
      {label}
    </span>
  );
}

function Message({ message }) {
  if (!message) return null;

  return (
    <div className={`ke-runtime__message ${MESSAGE_TONES[message.level] ?? MESSAGE_TONES.info}`}>
      {message.text}
    </div>
  );
}

function Summary({ items }) {
  if (!items.length) return null;

  return (
    <section className="ke-runtime__summary">
      {items.map((item) => (
        <div key={item.label} className="ke-runtime__summary-item">
          <div className="ke-runtime__summary-label">{item.label}</div>
          <div className="ke-runtime__summary-value">{item.value}</div>
        </div>
      ))}
    </section>
  );
}

function TableSection({ table }) {
  if (!table.rows.length) return null;

  return (
    <section className="ke-runtime__section">
      <div className="ke-runtime__section-title">{table.title}</div>
      <div className="ke-runtime__table-wrap">
        <table className="ke-runtime__table">
          <thead>
            <tr>
              {table.headers.map((header) => (
                <th key={header}>{header}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {table.rows.map((row) => (
              <tr key={row.key}>
                {row.cells.map((cell, index) => (
                  <td key={`${row.key}-${index}`}>{cell}</td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

function Details({ items }) {
  if (!items.length) return null;

  return (
    <section className="ke-runtime__section">
      <div className="ke-runtime__section-title">Details</div>
      <div className="ke-runtime__details">
        {items.map((item) => (
          <div key={item.label} className="ke-runtime__detail">
            <div className="ke-runtime__detail-label">{item.label}</div>
            <div className="ke-runtime__detail-value">{item.value}</div>
          </div>
        ))}
      </div>
    </section>
  );
}

function Controls({ ctx, controls }) {
  const [inputValue, setInputValue] = useState(controls?.input?.value ?? "");
  const [selectValue, setSelectValue] = useState(controls?.select?.options?.[0] ?? "");

  useEffect(() => {
    setInputValue(controls?.input?.value ?? "");
    setSelectValue(controls?.select?.options?.[0] ?? "");
  }, [controls]);

  if (!controls) return null;

  return (
    <section className="ke-runtime__section">
      <div className="ke-runtime__section-title">Controls</div>

      {controls.buttons?.length > 0 && (
        <div className="ke-runtime__buttons">
          {controls.buttons.map((button) => (
            <button
              key={button.id}
              onClick={() => ctx.pushEvent("action", { id: button.id })}
              className={`ke-runtime__button ${BUTTON_TONES[button.tone] ?? BUTTON_TONES.secondary}`}
            >
              {button.label}
            </button>
          ))}
        </div>
      )}

      {controls.select && (
        <div className="ke-runtime__form-row">
          <label className="ke-runtime__field">
            <span className="ke-runtime__field-label">{controls.select.label}</span>
            <select
              value={selectValue}
              onChange={(event) => setSelectValue(event.target.value)}
              className="ke-runtime__input"
            >
              {controls.select.options.map((option) => (
                <option key={option} value={option}>
                  {option}
                </option>
              ))}
            </select>
          </label>
          <button
            onClick={() => ctx.pushEvent("action", { id: controls.select.id, value: selectValue })}
            className={`ke-runtime__button ${BUTTON_TONES.primary}`}
          >
            Apply
          </button>
        </div>
      )}

      {controls.input && (
        <div className="ke-runtime__form-row">
          <label className="ke-runtime__field">
            <span className="ke-runtime__field-label">{controls.input.label}</span>
            <input
              value={inputValue}
              onChange={(event) => setInputValue(event.target.value)}
              className="ke-runtime__input"
            />
          </label>
          <button
            onClick={() =>
              ctx.pushEvent("action", {
                id: controls.submit?.id ?? controls.input.id,
                value: inputValue,
              })
            }
            className={`ke-runtime__button ${BUTTON_TONES[controls.submit?.tone ?? "primary"]}`}
          >
            {controls.submit?.label ?? "Apply"}
          </button>
        </div>
      )}
    </section>
  );
}

function RuntimePanel({ ctx, data }) {
  const [snapshot, setSnapshot] = useState(data);

  useEffect(() => {
    ctx.handleEvent("snapshot", (next) => {
      startTransition(() => setSnapshot(next));
    });
  }, [ctx]);

  return (
    <div className="ke-runtime">
      <div className="ke-runtime__header">
        <div className="ke-runtime__header-main">
          <div className="ke-runtime__kind">{snapshot.kind}</div>
          <h3 className="ke-runtime__title">{snapshot.title}</h3>
        </div>
        <Badge label={snapshot.status} />
      </div>

      <Message message={snapshot.message} />
      <Summary items={snapshot.summary} />

      <div className="ke-runtime__content">
        <div className="ke-runtime__main">
          <Controls ctx={ctx} controls={snapshot.controls} />
          {snapshot.tables.map((table) => (
            <TableSection key={table.title} table={table} />
          ))}
        </div>

        {snapshot.details.length > 0 && (
          <div className="ke-runtime__side">
            <Details items={snapshot.details} />
          </div>
        )}
      </div>
    </div>
  );
}
