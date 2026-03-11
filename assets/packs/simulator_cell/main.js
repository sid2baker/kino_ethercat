import "./main.css";

import React, { startTransition, useEffect, useMemo, useState } from "react";
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
  Dropdown,
  EmptyState,
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
  root.render(<SimulatorCell ctx={ctx} data={data} />);
}

function DeviceRow({ entry, position, onRemove }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } =
    useSortable({ id: entry.id });

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
      className={`ke95-simulator-cell__row${isDragging ? " ke95-simulator-cell__row--dragging" : ""}`}
    >
      <button className="ke95-simulator-cell__handle" title="Reorder" {...attributes} {...listeners}>
        ::
      </button>
      <Mono>{String(position + 1).padStart(2, "0")}</Mono>
      <Mono className="ke95-simulator-cell__name">{entry.default_name}</Mono>
      <Mono className="ke95-simulator-cell__driver">{entry.label}</Mono>
      <Button onClick={() => onRemove(entry.id)}>Remove</Button>
    </li>
  );
}

function runtimeTone(status) {
  return status === "running" ? "ok" : "neutral";
}

function messageTone(level) {
  return level === "error" ? "error" : "info";
}

function ringLabel(names, empty = "none") {
  return names?.length ? names.join(" -> ") : empty;
}

function SimulatorCell({ ctx, data }) {
  const [snapshot, setSnapshot] = useState(data);
  const [selected, setSelected] = useState(data.selected ?? []);
  const [driverToAdd, setDriverToAdd] = useState(data.available_drivers?.[0]?.module ?? "");

  useEffect(() => {
    ctx.handleEvent("snapshot", (next) => {
      startTransition(() => {
        setSnapshot(next);
        setSelected(next.selected ?? []);
      });
    });

    ctx.handleSync(() => {
      const active = document.activeElement;
      if (active instanceof HTMLElement && ctx.root.contains(active)) {
        active.blur();
      }
    });
  }, [ctx]);

  useEffect(() => {
    const current = snapshot.available_drivers ?? [];

    if (!current.some((driver) => driver.module === driverToAdd)) {
      setDriverToAdd(current[0]?.module ?? "");
    }
  }, [snapshot.available_drivers, driverToAdd]);

  const sensors = useSensors(useSensor(PointerSensor));
  const availableDrivers = snapshot.available_drivers ?? [];
  const runtime = snapshot.runtime ?? {};

  const selectedCountLabel = useMemo(
    () => `${selected.length} device${selected.length === 1 ? "" : "s"}`,
    [selected.length]
  );

  const handleDragEnd = ({ active, over }) => {
    if (!over || active.id === over.id) return;
    const oldIndex = selected.findIndex((entry) => entry.id === active.id);
    const newIndex = selected.findIndex((entry) => entry.id === over.id);
    const next = arrayMove(selected, oldIndex, newIndex);
    setSelected(next);
    ctx.pushEvent("reorder", { ids: next.map((entry) => entry.id) });
  };

  const handleRemove = (id) => {
    const next = selected.filter((entry) => entry.id !== id);
    setSelected(next);
    ctx.pushEvent("remove", { id });
  };

  return (
    <Shell
      title="EtherCAT Simulator"
      subtitle="Start a simulator-only ring and render the simulator panel."
      status={
        <>
          <Mono>{selectedCountLabel}</Mono>
          <StatusBadge tone={runtimeTone(runtime.status)}>{runtime.status ?? "offline"}</StatusBadge>
        </>
      }
    >
      <Panel
        title="Runtime"
        actions={
          <div className="ke95-toolbar ke95-simulator-cell__actions">
            <Button
              disabled={runtime.status !== "running" || !runtime.faults?.active_count}
              onClick={() => ctx.pushEvent("runtime_action", { id: "clear_faults" })}
            >
              Clear faults
            </Button>
            <Button
              disabled={runtime.status !== "running"}
              onClick={() => ctx.pushEvent("runtime_action", { id: "stop_runtime" })}
            >
              Stop simulator
            </Button>
          </div>
        }
      >
        <SummaryGrid items={runtime.summary ?? []} />
        <div className="ke95-simulator-cell__runtime-meta">
          <div className="ke95-simulator-cell__runtime-row">
            <div className="ke95-kicker">Configured ring</div>
            <Mono>{ringLabel(runtime.configured_names, "Add devices to define the virtual ring.")}</Mono>
          </div>
          <div className="ke95-simulator-cell__runtime-row">
            <div className="ke95-kicker">Running ring</div>
            <Mono>{ringLabel(runtime.running_names, "Simulator offline.")}</Mono>
          </div>
          <div className="ke95-simulator-cell__runtime-row">
            <div className="ke95-kicker">Faults</div>
            <Mono>{runtime.faults?.summary ?? "No active faults."}</Mono>
          </div>
        </div>

        <MessageLine tone={runtime.sync_tone ?? "info"}>{runtime.sync_message}</MessageLine>
        <MessageLine tone={messageTone(runtime.message?.level)}>{runtime.message?.text}</MessageLine>
      </Panel>

      <Panel
        title="Add device"
        actions={
          <Button onClick={() => ctx.pushEvent("reset_defaults", {})}>
            Reset loopback
          </Button>
        }
      >
        <div className="ke95-toolbar">
          <ControlField label="Driver" className="ke95-fill">
            <Dropdown
              value={driverToAdd}
              className="ke95-fill"
              onChange={(event) => setDriverToAdd(event.target.value)}
            >
              {availableDrivers.map((driver) => (
                <option key={driver.module} value={driver.module}>
                  {driver.label}
                </option>
              ))}
            </Dropdown>
          </ControlField>
          <Button disabled={!driverToAdd} onClick={() => ctx.pushEvent("add_device", { driver: driverToAdd })}>
            Add
          </Button>
        </div>
      </Panel>

      <Panel title="Device order">
        {selected.length === 0 ? (
          <EmptyState>Add one or more simulator devices to build the virtual ring.</EmptyState>
        ) : (
          <DndContext
            sensors={sensors}
            collisionDetection={closestCenter}
            modifiers={[restrictToVerticalAxis, restrictToParentElement]}
            onDragEnd={handleDragEnd}
          >
            <SortableContext
              items={selected.map((entry) => entry.id)}
              strategy={verticalListSortingStrategy}
            >
              <ul className="ke95-list">
                {selected.map((entry, index) => (
                  <DeviceRow
                    key={entry.id}
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
