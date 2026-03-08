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
    <svg width="14" height="14" viewBox="0 0 14 14" fill="currentColor" className="text-gray-300">
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

function SlaveRow({ entry, onRemove, onOptsChange }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } =
    useSortable({ id: entry.name });

  const [columnsInput, setColumnsInput] = useState(entry.columns ?? "");

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.4 : 1,
    zIndex: isDragging ? 10 : undefined,
  };

  const commitColumns = () => {
    const val =
      columnsInput === "" ? null : Math.max(1, Math.min(16, Number(columnsInput)));
    onOptsChange(entry.name, val);
  };

  return (
    <li
      ref={setNodeRef}
      style={style}
      className="flex items-center gap-2 px-2 py-1.5 rounded bg-white border border-gray-200 shadow-sm"
    >
      {/* Drag handle */}
      <button
        className="cursor-grab active:cursor-grabbing touch-none text-gray-300 hover:text-gray-500 flex-shrink-0"
        {...attributes}
        {...listeners}
      >
        <GripIcon />
      </button>

      {/* Slave name */}
      <span className="font-mono text-sm text-gray-700 flex-1">{entry.name}</span>

      {/* Per-row input */}
      <label className="flex items-center gap-1 text-xs text-gray-400">
        <span>per row</span>
        <input
          type="number"
          min="1"
          max="16"
          placeholder="auto"
          className="w-11 border border-gray-300 rounded px-1 py-0.5 font-mono text-xs focus:outline-none focus:border-blue-400 text-gray-700"
          value={columnsInput}
          onChange={(e) => setColumnsInput(e.target.value)}
          onBlur={commitColumns}
          onKeyDown={(e) => e.key === "Enter" && commitColumns()}
        />
      </label>

      {/* Remove button */}
      <button
        onClick={() => onRemove(entry.name)}
        className="text-gray-300 hover:text-red-400 transition-colors flex-shrink-0"
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
  const [status, setStatus] = useState(data.status ?? "ok");

  useEffect(() => {
    ctx.handleEvent("refreshed", ({ selected, status }) => {
      setSelected(selected);
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

  const handleOptsChange = (name, columns) => {
    setSelected(selected.map((s) => (s.name === name ? { ...s, columns } : s)));
    ctx.pushEvent("update_opts", { name, columns });
  };

  return (
    <div className="p-3 space-y-2 font-sans text-sm select-none">
      {/* Header */}
      <div className="flex items-center gap-2">
        <span className="text-gray-600 font-medium">EtherCAT slaves</span>
        <button
          onClick={() => ctx.pushEvent("refresh")}
          className="px-2 py-0.5 text-xs border border-gray-300 rounded text-gray-500 hover:bg-gray-50 hover:border-gray-400 transition-colors"
        >
          Refresh
        </button>
        {status === "not_running" && (
          <span className="text-xs text-amber-600 font-mono">EtherCAT not running</span>
        )}
      </div>

      {/* Sortable list */}
      {selected.length === 0 ? (
        <p className="text-xs text-gray-400 font-mono">
          {status === "not_running"
            ? "Start EtherCAT first, then click Refresh."
            : "No slaves — click Refresh to load."}
        </p>
      ) : (
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
            <ul className="space-y-1.5">
              {selected.map((entry) => (
                <SlaveRow
                  key={entry.name}
                  entry={entry}
                  onRemove={handleRemove}
                  onOptsChange={handleOptsChange}
                />
              ))}
            </ul>
          </SortableContext>
        </DndContext>
      )}
    </div>
  );
}
