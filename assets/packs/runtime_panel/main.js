import "./main.css";

import React, { startTransition, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

export async function init(ctx, data) {
  await ctx.importCSS("main.css");
  const root = createRoot(ctx.root);
  root.render(<RuntimePanel ctx={ctx} data={data} />);
}

const STATUS_STYLES = {
  info: "bg-sky-100 text-sky-800",
  error: "bg-rose-100 text-rose-800",
};

const BUTTON_STYLES = {
  primary: "border-stone-800 bg-stone-800 text-white hover:bg-stone-700",
  secondary: "border-stone-300 bg-white text-stone-600 hover:border-stone-400 hover:bg-stone-100",
  danger: "border-rose-600 bg-rose-600 text-white hover:bg-rose-500",
};

function Badge({ label, tone }) {
  return (
    <span className={`inline-flex items-center rounded-full px-2 py-0.5 font-mono text-[11px] font-medium ${tone}`}>
      {label}
    </span>
  );
}

function Message({ message }) {
  if (!message) return null;

  return (
    <div className={`rounded-xl border px-3 py-2 font-mono text-xs ${STATUS_STYLES[message.level] ?? STATUS_STYLES.info}`}>
      {message.text}
    </div>
  );
}

function Summary({ items }) {
  if (!items.length) return null;

  return (
    <div className="grid gap-2 md:grid-cols-2 xl:grid-cols-3">
      {items.map((item) => (
        <div key={item.label} className="rounded-xl border border-stone-200 bg-white/80 px-3 py-2">
          <div className="text-[11px] uppercase tracking-[0.18em] text-stone-400">{item.label}</div>
          <div className="mt-1 font-mono text-xs text-stone-700">{item.value}</div>
        </div>
      ))}
    </div>
  );
}

function TableSection({ table }) {
  if (!table.rows.length) return null;

  return (
    <section className="rounded-2xl border border-stone-200 bg-white/80 p-3">
      <div className="mb-3 text-[11px] font-semibold uppercase tracking-[0.18em] text-stone-400">{table.title}</div>
      <div className="overflow-x-auto">
        <table className="w-full border-collapse">
          <thead>
            <tr className="text-left text-[11px] uppercase tracking-[0.18em] text-stone-400">
              {table.headers.map((header) => (
                <th key={header} className="pb-2 pr-3">{header}</th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-stone-100">
            {table.rows.map((row) => (
              <tr key={row.key}>
                {row.cells.map((cell, index) => (
                  <td key={`${row.key}-${index}`} className="py-2 pr-3 font-mono text-xs text-stone-600">
                    {cell}
                  </td>
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
    <section className="rounded-2xl border border-stone-200 bg-white/80 p-3">
      <div className="mb-3 text-[11px] font-semibold uppercase tracking-[0.18em] text-stone-400">Details</div>
      <div className="space-y-2">
        {items.map((item) => (
          <div key={item.label} className="rounded-xl bg-stone-50 px-3 py-2">
            <div className="text-[11px] uppercase tracking-[0.18em] text-stone-400">{item.label}</div>
            <div className="mt-1 break-all font-mono text-xs text-stone-700">{item.value}</div>
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
    <section className="rounded-2xl border border-stone-200 bg-white/80 p-3">
      <div className="mb-3 text-[11px] font-semibold uppercase tracking-[0.18em] text-stone-400">Controls</div>

      {controls.buttons?.length > 0 && (
        <div className="flex flex-wrap gap-2">
          {controls.buttons.map((button) => (
            <button
              key={button.id}
              onClick={() => ctx.pushEvent("action", { id: button.id })}
              className={`rounded-full border px-3 py-1.5 text-xs font-medium transition ${BUTTON_STYLES[button.tone] ?? BUTTON_STYLES.secondary}`}
            >
              {button.label}
            </button>
          ))}
        </div>
      )}

      {controls.select && (
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <label className="text-[11px] uppercase tracking-[0.18em] text-stone-400">{controls.select.label}</label>
          <select
            value={selectValue}
            onChange={(event) => setSelectValue(event.target.value)}
            className="rounded-xl border border-stone-300 bg-white px-3 py-2 font-mono text-xs text-stone-700"
          >
            {controls.select.options.map((option) => (
              <option key={option} value={option}>{option}</option>
            ))}
          </select>
          <button
            onClick={() => ctx.pushEvent("action", { id: controls.select.id, value: selectValue })}
            className={`rounded-full border px-3 py-1.5 text-xs font-medium transition ${BUTTON_STYLES.primary}`}
          >
            Apply
          </button>
        </div>
      )}

      {controls.input && (
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <label className="text-[11px] uppercase tracking-[0.18em] text-stone-400">{controls.input.label}</label>
          <input
            value={inputValue}
            onChange={(event) => setInputValue(event.target.value)}
            className="rounded-xl border border-stone-300 bg-white px-3 py-2 font-mono text-xs text-stone-700"
          />
          <button
            onClick={() =>
              ctx.pushEvent("action", {
                id: controls.submit?.id ?? controls.input.id,
                value: inputValue,
              })
            }
            className={`rounded-full border px-3 py-1.5 text-xs font-medium transition ${BUTTON_STYLES[controls.submit?.tone ?? "primary"]}`}
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
    <div className="kino-ethercat-runtime space-y-3 p-4 font-sans text-sm">
      <div className="flex flex-wrap items-center gap-2">
        <h3 className="text-sm font-semibold tracking-tight text-stone-800">{snapshot.title}</h3>
        <Badge label={snapshot.status} tone="bg-stone-200 text-stone-700" />
      </div>

      <Message message={snapshot.message} />
      <Summary items={snapshot.summary} />
      <Controls ctx={ctx} controls={snapshot.controls} />
      {snapshot.tables.map((table) => (
        <TableSection key={table.title} table={table} />
      ))}
      <Details items={snapshot.details} />
    </div>
  );
}
