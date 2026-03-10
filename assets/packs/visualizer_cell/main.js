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

import {
  Button,
  ControlField,
  EmptyState,
  Frame,
  Input,
  Mono,
  Panel,
  Shell,
  StatusBadge,
} from "../../ui/react95";

export async function init(ctx, data) {
  await ctx.importCSS("main.css");
  const root = createRoot(ctx.root);
  root.render(<VisualizerCell ctx={ctx} data={data} />);
}

function statusTone(status) {
  return status === "ok" ? "ok" : status === "not_running" ? "warn" : "neutral";
}

function SlaveRow({ entry, position, onRemove }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } =
    useSortable({ id: entry.name });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.6 : 1,
    zIndex: isDragging ? 10 : undefined,
  };

  return (
    <li
      ref={setNodeRef}
      style={style}
      className={`ke95-visualizer__row${isDragging ? " ke95-visualizer__row--dragging" : ""}`}
    >
      <button className="ke95-visualizer__handle" title="Reorder" {...attributes} {...listeners}>
        ::
      </button>
      <Mono>{String(position + 1).padStart(2, "0")}</Mono>
      <Mono>{entry.name}</Mono>
      <Button onClick={() => onRemove(entry.name)}>Remove</Button>
    </li>
  );
}

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
  }, [ctx]);

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
    <Shell
      title="Dashboard slaves"
      subtitle={`${selected.length} selected`}
      status={<StatusBadge tone={statusTone(status)}>{status === "not_running" ? "offline" : status}</StatusBadge>}
      toolbar={<Button onClick={() => ctx.pushEvent("refresh")}>Refresh</Button>}
    >
      <Panel title="Layout">
        <div className="ke95-toolbar">
          <ControlField label="Columns" help="Leave empty for automatic layout.">
            <Input
              type="number"
              min="1"
              max="4"
              placeholder="auto"
              className="ke95-fill"
              value={columnsInput}
              onChange={(event) => setColumnsInput(event.target.value)}
              onBlur={commitColumns}
              onKeyDown={(event) => event.key === "Enter" && commitColumns()}
            />
          </ControlField>
        </div>
      </Panel>

      <Panel title="Selected slaves">
        {selected.length === 0 ? (
          <EmptyState>
            {status === "not_running"
              ? "Start EtherCAT, then refresh to load available slaves."
              : "No slaves selected. Refresh to load the current bus inventory."}
          </EmptyState>
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
              <ul className="ke95-list">
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
        )}
      </Panel>
    </Shell>
  );
}
