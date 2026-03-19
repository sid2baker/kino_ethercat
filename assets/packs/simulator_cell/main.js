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
  Checkbox,
  Columns,
  ControlField,
  Dropdown,
  EmptyState,
  Input,
  InlineButtons,
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
  root.render(<SimulatorCell ctx={ctx} data={data} />);
}

function DeviceRow({ entry, position, onRename, onRemove, disabled }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } =
    useSortable({ id: entry.id, disabled });
  const [nameValue, setNameValue] = useState(entry.name ?? "");

  useEffect(() => {
    setNameValue(entry.name ?? "");
  }, [entry.name]);

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.6 : 1,
    zIndex: isDragging ? 10 : undefined,
  };

  const commitName = () => {
    if (disabled) return;
    if (nameValue === (entry.name ?? "")) return;
    onRename(entry.id, nameValue);
  };

  return (
    <li
      ref={setNodeRef}
      style={style}
      className={`ke95-simulator-cell__row${isDragging ? " ke95-simulator-cell__row--dragging" : ""}`}
    >
      <button
        className="ke95-simulator-cell__handle"
        title="Reorder"
        disabled={disabled}
        {...attributes}
        {...listeners}
      >
        ::
      </button>
      <Mono>{String(position + 1).padStart(2, "0")}</Mono>
      <Input
        value={nameValue}
        className="ke95-fill"
        aria-label={`Device name ${position + 1}`}
        disabled={disabled}
        onChange={(event) => setNameValue(event.target.value)}
        onBlur={commitName}
        onKeyDown={(event) => {
          if (event.key === "Enter") {
            event.currentTarget.blur();
          }
        }}
      />
      <Mono className="ke95-simulator-cell__driver">{entry.label}</Mono>
      <Button disabled={disabled} onClick={() => onRemove(entry.id)}>Remove</Button>
    </li>
  );
}

function ConnectionRow({ entry, onRemove, disabled }) {
  return (
    <li className="ke95-simulator-cell__connection">
      <Mono className="ke95-simulator-cell__connection-label">{entry.source_label}</Mono>
      <Mono className="ke95-simulator-cell__connection-arrow">-&gt;</Mono>
      <Mono className="ke95-simulator-cell__connection-label">{entry.target_label}</Mono>
      <Button disabled={disabled} onClick={() => onRemove(entry.key)}>Remove</Button>
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

function transportLabel(transport) {
  switch (transport) {
    case "raw_socket":
      return "Raw socket";
    case "raw_socket_redundant":
      return "Raw socket + redundant";
    default:
      return "UDP";
  }
}

function SimpleModeContent({ snapshot }) {
  const defaultRing = ringLabel(
    (snapshot.selected ?? []).map((entry) => entry.name),
    "coupler -> inputs -> outputs"
  );

  return (
    <Stack>
      <Panel title="What this is">
        <Stack compact className="ke95-simulator-cell__intro-copy">
          <div>
            This smart cell starts <Mono>EtherCAT.Simulator</Mono> using{" "}
            <Mono>{transportLabel(snapshot.transport)}</Mono> transport, so you can learn EtherCAT without real hardware.
          </div>
          <div>
            By default it creates a small loopback bench with a coupler, an input card, and an
            output card.
          </div>
        </Stack>
      </Panel>

      <Panel title="How to use it">
        <Stack compact>
          <PropertyList
            items={[
              { label: "Default ring", value: defaultRing },
              { label: "Transport", value: transportLabel(snapshot.transport) },
              { label: "Generated tabs", value: "Introduction, Simulator, Faults" },
            ]}
          />
          <ol className="ke95-simulator-cell__steps">
            <li>Evaluate this cell to start the simulator workspace.</li>
            <li>Use the EtherCAT Setup smart cell. It will detect the running simulator transport.</li>
            <li>Evaluate the generated setup cell to move from PREOP to OP.</li>
            <li>
              Write notebook cells with <Mono>EtherCAT.Simulator.Fault</Mono> plus{" "}
              <Mono>EtherCAT.Simulator.Transport.Udp.Fault</Mono> or{" "}
              <Mono>EtherCAT.Simulator.Transport.Raw.Fault</Mono> when you want scripted drills.
            </li>
            <li>Enable Expert mode if you want to rename devices, reorder the ring, or add connections.</li>
          </ol>
        </Stack>
      </Panel>
    </Stack>
  );
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
  const expertMode = Boolean(snapshot.expert_mode);
  const configLocked = runtime.status === "running";

  const selectedCountLabel = useMemo(
    () => `${selected.length} device${selected.length === 1 ? "" : "s"}`,
    [selected.length]
  );

  const handleDragEnd = ({ active, over }) => {
    if (configLocked) return;
    if (!over || active.id === over.id) return;
    const oldIndex = selected.findIndex((entry) => entry.id === active.id);
    const newIndex = selected.findIndex((entry) => entry.id === over.id);
    const next = arrayMove(selected, oldIndex, newIndex);
    setSelected(next);
    ctx.pushEvent("reorder", { ids: next.map((entry) => entry.id) });
  };

  const handleRemove = (id) => {
    if (configLocked) return;
    const next = selected.filter((entry) => entry.id !== id);
    setSelected(next);
    ctx.pushEvent("remove", { id });
  };

  const handleRename = (id, name) => {
    if (configLocked) return;
    setSelected((current) =>
      current.map((entry) => (entry.id === id ? { ...entry, name } : entry))
    );
    ctx.pushEvent("rename", { id, name });
  };

  return (
    <Shell
      title="EtherCAT Simulator"
      subtitle={snapshot.description}
      status={
        <>
          <Mono>{selectedCountLabel}</Mono>
          <StatusBadge tone={runtimeTone(runtime.status)}>{runtime.status ?? "offline"}</StatusBadge>
        </>
      }
      toolbar={
        <Checkbox
          checked={expertMode}
          label="Expert mode"
          onChange={(event) => ctx.pushEvent("set_expert_mode", { enabled: event.target.checked })}
        />
      }
    >
      {expertMode ? (
        <Stack className="ke95-simulator-cell">
          <Panel
            title="Runtime"
            actions={
              <InlineButtons className="ke95-simulator-cell__actions">
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
              </InlineButtons>
            }
          >
            <Stack compact>
              <SummaryGrid items={runtime.summary ?? []} />
              <Columns minWidth="14rem">
                <ControlField label="Transport" className="ke95-fill">
                  <Dropdown
                    value={snapshot.transport ?? "udp"}
                    className="ke95-fill"
                    disabled={configLocked}
                    onChange={(event) => ctx.pushEvent("set_transport", { transport: event.target.value })}
                  >
                    {(snapshot.available_transports ?? []).map((t) => (
                      <option key={t.value} value={t.value} disabled={!t.available}>
                        {t.label}{!t.available && t.hint ? ` (${t.hint})` : ""}
                      </option>
                    ))}
                  </Dropdown>
                </ControlField>
              </Columns>
              <PropertyList
                minWidth="12rem"
                items={[
                  {
                    label: "Configured ring",
                    value: ringLabel(runtime.configured_names, "Add devices to define the virtual ring."),
                  },
                  {
                    label: "Configured transport",
                    value: transportLabel(runtime.configured_transport ?? snapshot.transport),
                  },
                  { label: "Running ring", value: ringLabel(runtime.running_names, "Simulator offline.") },
                  {
                    label: "Running transport",
                    value:
                      runtime.running_transport === "disabled"
                        ? "disabled"
                        : transportLabel(runtime.running_transport),
                  },
                  { label: "Faults", value: runtime.faults?.summary ?? "No active faults." },
                  {
                    label: "Connections",
                    value: `configured ${runtime.configured_connection_count ?? 0} / running ${runtime.running_connection_count ?? 0}`,
                  },
                ]}
              />
              {configLocked ? (
                <MessageLine tone="info">
                  Stop the simulator before changing transport, devices, or connections.
                </MessageLine>
              ) : null}
              <MessageLine tone={runtime.sync_tone ?? "info"}>{runtime.sync_message}</MessageLine>
              <MessageLine tone={messageTone(runtime.message?.level)}>{runtime.message?.text}</MessageLine>
            </Stack>
          </Panel>

          <Panel
            title="Add device"
            actions={
              <Button disabled={configLocked} onClick={() => ctx.pushEvent("reset_defaults", {})}>
                Reset loopback
              </Button>
            }
          >
            <Columns minWidth="14rem">
              <ControlField label="Driver" className="ke95-fill">
                <Dropdown
                  value={driverToAdd}
                  className="ke95-fill"
                  disabled={configLocked}
                  onChange={(event) => setDriverToAdd(event.target.value)}
                >
                  {availableDrivers.map((driver) => (
                    <option key={driver.module} value={driver.module}>
                      {driver.label}
                    </option>
                  ))}
                </Dropdown>
              </ControlField>
              <InlineButtons className="ke95-simulator-cell__add-actions">
                <Button
                  disabled={configLocked || !driverToAdd}
                  onClick={() => ctx.pushEvent("add_device", { driver: driverToAdd })}
                >
                  Add
                </Button>
              </InlineButtons>
            </Columns>
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
                        disabled={configLocked}
                        onRename={handleRename}
                        onRemove={handleRemove}
                      />
                    ))}
                  </ul>
                </SortableContext>
              </DndContext>
            )}
          </Panel>

          <Panel
            title="Connections"
            actions={
              <Button
                disabled={configLocked || selected.length === 0}
                onClick={() => ctx.pushEvent("auto_wire_matching", {})}
              >
                Auto-wire matching signals
              </Button>
            }
          >
            {snapshot.connections?.length ? (
              <div className="ke95-simulator-cell__connections">
                <ul className="ke95-list">
                  {snapshot.connections.map((entry) => (
                    <ConnectionRow
                      key={entry.key}
                      entry={entry}
                      disabled={configLocked}
                      onRemove={(key) => ctx.pushEvent("remove_connection", { key })}
                    />
                  ))}
                </ul>
              </div>
            ) : (
              <EmptyState>
                No configured connections. Auto-wire matching output and input signal names to create loopback links.
              </EmptyState>
            )}
          </Panel>
        </Stack>
      ) : (
        <SimpleModeContent snapshot={snapshot} />
      )}
    </Shell>
  );
}
