import "./main.css";

import React, { useEffect, useMemo, useState } from "react";
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
  Checkbox,
  EmptyState,
  Fieldset,
  Mono,
  Panel,
  Shell,
  Stack,
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

function naturalCompare(a, b) {
  return a.localeCompare(b, undefined, { numeric: true, sensitivity: "base" });
}

function buildSignalGroups(selected, available) {
  const merged = new Map();

  for (const entry of available) merged.set(entry.key, entry);
  for (const entry of selected) if (entry.available) merged.set(entry.key, entry);

  return [...merged.values()]
    .sort((left, right) => {
      const slaveOrder = (left.slave_index ?? Number.MAX_SAFE_INTEGER) - (right.slave_index ?? Number.MAX_SAFE_INTEGER);
      if (slaveOrder !== 0) return slaveOrder;

      const signalOrder = (left.signal_index ?? Number.MAX_SAFE_INTEGER) - (right.signal_index ?? Number.MAX_SAFE_INTEGER);
      if (signalOrder !== 0) return signalOrder;

      const slaveNameOrder = naturalCompare(left.slave ?? "", right.slave ?? "");
      if (slaveNameOrder !== 0) return slaveNameOrder;

      return naturalCompare(left.signal ?? "", right.signal ?? "");
    })
    .reduce((groups, entry) => {
      const last = groups[groups.length - 1];

      if (last && last.slave === entry.slave) {
        last.signals.push(entry);
        return groups;
      }

      return [...groups, { slave: entry.slave, signals: [entry] }];
    }, []);
}

function SelectedRow({ entry, onRemove }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } =
    useSortable({ id: entry.key });

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
      className={`ke95-visualizer__selected-row${isDragging ? " ke95-visualizer__selected-row--dragging" : ""}`}
    >
      <button className="ke95-visualizer__handle" title="Reorder" {...attributes} {...listeners}>
        ::
      </button>
      <div className="ke95-visualizer__selected-copy">
        <div className="ke95-visualizer__selected-line">
          <Mono>{entry.signal}</Mono>
          <StatusBadge tone={entry.resolved_widget === "switch" ? "warn" : "ok"}>
            {entry.widget_label}
          </StatusBadge>
          {!entry.available ? <StatusBadge tone="warn">stale</StatusBadge> : null}
        </div>
        <Mono>{entry.slave}</Mono>
      </div>
      <Button onClick={() => onRemove(entry.key)}>Remove</Button>
    </li>
  );
}

function SignalCheckbox({ entry, checked, onToggle }) {
  return (
    <div className="ke95-visualizer__signal">
      <Checkbox
        checked={checked}
        label={entry.signal}
        onChange={(event) => onToggle(entry.key, event.target.checked)}
      />
    </div>
  );
}

function VisualizerCell({ ctx, data }) {
  const [snapshot, setSnapshot] = useState(data);

  useEffect(() => {
    ctx.handleEvent("snapshot", (next) => {
      setSnapshot(next);
    });
  }, [ctx]);

  const sensors = useSensors(useSensor(PointerSensor));
  const selected = snapshot.selected ?? [];
  const available = snapshot.available ?? [];
  const status = snapshot.status ?? "ok";
  const selectedByKey = useMemo(() => new Map(selected.map((entry) => [entry.key, entry])), [selected]);
  const groups = useMemo(() => buildSignalGroups(selected, available), [selected, available]);

  const handleDragEnd = ({ active, over }) => {
    if (!over || active.id === over.id) return;
    const oldIndex = selected.findIndex((entry) => entry.key === active.id);
    const newIndex = selected.findIndex((entry) => entry.key === over.id);
    const next = arrayMove(selected, oldIndex, newIndex);
    ctx.pushEvent("reorder", { keys: next.map((entry) => entry.key) });
  };

  const toggleSignal = (key, checked) => {
    ctx.pushEvent(checked ? "add" : "remove", { key });
  };

  return (
    <Shell
      title={snapshot.title ?? "Signal visualizer"}
      subtitle={`${selected.length} selected`}
      status={
        <StatusBadge tone={statusTone(status)}>
          {status === "not_running" ? "offline" : status}
        </StatusBadge>
      }
    >
      <Stack className="ke95-visualizer">
        <Panel title="Selected signals">
          {selected.length === 0 ? (
            <EmptyState>Pick one output and one input.</EmptyState>
          ) : (
            <DndContext
              sensors={sensors}
              collisionDetection={closestCenter}
              modifiers={[restrictToVerticalAxis, restrictToParentElement]}
              onDragEnd={handleDragEnd}
            >
              <SortableContext
                items={selected.map((entry) => entry.key)}
                strategy={verticalListSortingStrategy}
              >
                <ul className="ke95-list ke95-visualizer__selected-list">
                  {selected.map((entry, index) => (
                    <SelectedRow
                      key={entry.key}
                      entry={entry}
                      onRemove={(key) => ctx.pushEvent("remove", { key })}
                    />
                  ))}
                </ul>
              </SortableContext>
            </DndContext>
          )}
        </Panel>

        <Panel title="Signals on bus">
          {groups.length === 0 ? (
            <EmptyState>
              {status === "not_running"
                ? "Evaluate the setup cell first."
                : "No supported signals found."}
            </EmptyState>
          ) : (
            <Stack className="ke95-visualizer__groups">
              {groups.map((group) => (
                <Fieldset key={group.slave} legend={group.slave}>
                  <div className="ke95-visualizer__group">
                    {group.signals.map((entry) => (
                      <SignalCheckbox
                        key={entry.key}
                        entry={entry}
                        checked={selectedByKey.has(entry.key)}
                        onToggle={toggleSignal}
                      />
                    ))}
                  </div>
                </Fieldset>
              ))}
            </Stack>
          )}
        </Panel>
      </Stack>
    </Shell>
  );
}
