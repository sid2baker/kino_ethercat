import "./main.css";

import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  DndContext,
  closestCenter,
  PointerSensor,
  useSensor,
  useSensors,
} from "@dnd-kit/core";
import {
  SortableContext,
  verticalListSortingStrategy,
  useSortable,
  arrayMove,
} from "@dnd-kit/sortable";
import { restrictToVerticalAxis, restrictToParentElement } from "@dnd-kit/modifiers";
import { CSS } from "@dnd-kit/utilities";

export async function init(ctx, data) {
  await ctx.importCSS("main.css");
  const root = createRoot(ctx.root);
  root.render(<VisualizerCell ctx={ctx} data={data} />);
}

// ── Drag handle icon ──────────────────────────────────────────────────────────

function GripIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="currentColor">
      <circle cx="4" cy="3" r="1.2" />
      <circle cx="10" cy="3" r="1.2" />
      <circle cx="4" cy="7" r="1.2" />
      <circle cx="10" cy="7" r="1.2" />
      <circle cx="4" cy="11" r="1.2" />
      <circle cx="10" cy="11" r="1.2" />
    </svg>
  );
}

function TrashIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="3 6 5 6 21 6" />
      <path d="M19 6l-1 14H6L5 6" />
      <path d="M10 11v6M14 11v6" />
      <path d="M9 6V4h6v2" />
    </svg>
  );
}

// ── Sortable slave row ────────────────────────────────────────────────────────

function SlaveRow({ entry, position, onRemove }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } =
    useSortable({ id: entry.name });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.4 : 1,
    zIndex: isDragging ? 10 : undefined,
  };

  return (
    <li
      ref={setNodeRef}
      style={style}
      className={`ke-visualizer__row${isDragging ? " ke-visualizer__row--dragging" : ""}`}
    >
      <button
        className="ke-visualizer__handle"
        title="Reorder"
        {...attributes}
        {...listeners}
      >
        <GripIcon />
      </button>

      <span className="ke-visualizer__position">{String(position + 1).padStart(2, "0")}</span>

      <span className="ke-visualizer__name">{entry.name}</span>

      <button
        onClick={() => onRemove(entry.name)}
        className="ke-visualizer__remove"
        title="Remove"
      >
        <TrashIcon />
      </button>
    </li>
  );
}

// ── Main component ────────────────────────────────────────────────────────────

function VisualizerCell({ ctx, data }) {
  const [selected, setSelected] = useState(data.selected ?? []);
  const [columnsInput, setColumnsInput] = useState(data.columns ?? "");
  const [status, setStatus] = useState(data.status ?? "ok");

  useEffect(() => {
    ctx.handleEvent("refreshed", ({ selected, columns, status }) => {
      setSelected(selected);
      setColumnsInput(columns ?? "");
      setStatus(status);
    });
    ctx.handleSync(() => {
      const active = document.activeElement;
      if (active instanceof HTMLElement && ctx.root.contains(active)) {
        active.blur();
      }
    });
  }, []);

  const sensors = useSensors(useSensor(PointerSensor));

  const handleDragEnd = ({ active, over }) => {
    if (!over || active.id === over.id) return;
    const oldIndex = selected.findIndex((s) => s.name === active.id);
    const newIndex = selected.findIndex((s) => s.name === over.id);
    const next = arrayMove(selected, oldIndex, newIndex);
    setSelected(next);
    ctx.pushEvent("reorder", { names: next.map((s) => s.name) });
  };

  const handleRemove = (name) => {
    const next = selected.filter((s) => s.name !== name);
    setSelected(next);
    ctx.pushEvent("remove", { name });
  };

  const commitColumns = () => {
    const columns =
      columnsInput === "" ? null : Math.max(1, Math.min(4, Number(columnsInput)));
    setColumnsInput(columns ?? "");
    ctx.pushEvent("update_columns", { columns });
  };

  return (
    <div className="ke-visualizer">
      <div className="ke-visualizer__toolbar">
        <div className="ke-visualizer__heading">
          <div className="ke-visualizer__title">Dashboard slaves</div>
          <div className="ke-visualizer__meta">
            {selected.length} selected
            <span className={`ke-visualizer__status ke-visualizer__status--${status}`}>
              {status === "not_running" ? "master offline" : status}
            </span>
          </div>
        </div>

        <div className="ke-visualizer__controls">
          <label className="ke-visualizer__control">
            <span>Columns</span>
            <input
              type="number"
              min="1"
              max="4"
              placeholder="auto"
              className="ke-visualizer__input"
              value={columnsInput}
              onChange={(e) => setColumnsInput(e.target.value)}
              onBlur={commitColumns}
              onKeyDown={(e) => e.key === "Enter" && commitColumns()}
            />
          </label>

          <button
            onClick={() => ctx.pushEvent("refresh")}
            className="ke-visualizer__button"
          >
            Refresh
          </button>
        </div>
      </div>

      {selected.length === 0 ? (
        <div className="ke-visualizer__empty">
          {status === "not_running"
            ? "Start EtherCAT, then refresh to load available slaves."
            : "No slaves selected. Refresh to load the current bus inventory."}
        </div>
      ) : (
        <div className="ke-visualizer__body">
          <div className="ke-visualizer__list-header">
            <span className="ke-visualizer__list-header-index">#</span>
            <span className="ke-visualizer__list-header-name">Slave</span>
          </div>

          <DndContext
            sensors={sensors}
            collisionDetection={closestCenter}
            modifiers={[restrictToVerticalAxis, restrictToParentElement]}
            onDragEnd={handleDragEnd}
          >
            <SortableContext
              items={selected.map((s) => s.name)}
              strategy={verticalListSortingStrategy}
            >
              <ul className="ke-visualizer__list">
                {selected.map((entry, index) => (
                  <SlaveRow
                    key={entry.name}
                    entry={entry}
                    position={index}
                    onRemove={handleRemove}
                  />
                ))}
              </ul>
            </SortableContext>
          </DndContext>
        </div>
      )}
    </div>
  );
}
