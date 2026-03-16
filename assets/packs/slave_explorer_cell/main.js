import "./main.css";

import React, { startTransition, useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";

import {
  Button,
  ControlField,
  DataTable,
  Dropdown,
  EmptyState,
  Input,
  MessageLine,
  Panel,
  PropertyList,
  Shell,
  Stack,
  Tab,
  Tabs,
  TextArea,
} from "../../ui/react95";
import { BusSetupFields, BusSetupSummary, transportLabel, transportSourceLabel } from "../../ui/bus_setup";

export async function init(ctx, payload) {
  await ctx.importCSS("main.css");
  const root = createRoot(ctx.root);
  root.render(<SlaveExplorerCell ctx={ctx} payload={payload} />);
}

function SlaveExplorerCell({ ctx, payload }) {
  const [state, setState] = useState(payload);
  const [values, setValues] = useState(payload.values ?? {});
  const [udpPortInput, setUdpPortInput] = useState(String(payload.bus?.port ?? 34980));
  const valuesRef = useRef(values);
  const slaveSelectionName = useRef(`slave-selection-${Math.random().toString(36).slice(2)}`).current;

  useEffect(() => {
    valuesRef.current = values;
  }, [values]);

  useEffect(() => {
    setUdpPortInput(String(state.bus?.port ?? 34980));
  }, [state.bus?.transport, state.bus?.port]);

  useEffect(() => {
    ctx.handleEvent("snapshot", (nextPayload) => {
      startTransition(() => {
        setState(nextPayload);
        setValues(nextPayload.values ?? {});
      });
    });

    ctx.handleSync(() => {
      ctx.pushEvent("update", valuesRef.current);
    });
  }, [ctx]);

  const update = (patch) => {
    const nextValues = { ...values, ...patch };
    setValues(nextValues);
    ctx.pushEvent("update", nextValues);
  };

  const commitUdpPort = (rawValue) => {
    const trimmed = String(rawValue ?? "").trim();
    const parsed = Number.parseInt(trimmed, 10);
    const port = Number.isInteger(parsed) && parsed > 0 ? parsed : 34980;

    setUdpPortInput(String(port));
    update({ port, transport_mode: "manual" });
  };

  const busState = {
    ...state.bus,
    transport: values.transport ?? state.bus.transport,
    interface: values.interface ?? state.bus.interface,
    backup_interface: values.backup_interface ?? state.bus.backup_interface,
    host: values.host ?? state.bus.host,
    port: values.port ?? state.bus.port,
  };

  const inventory = state.capture.inventory ?? [];
  const selectedSlave = values.slave ?? state.capture.slave ?? "";

  const selectSlave = (nextSlave) => {
    const previousSlave = selectedSlave;
    const currentDriverName = values.driver_name ?? state.scaffold.driver_name ?? "";
    const patch = { slave: nextSlave };

    if (!currentDriverName || currentDriverName === suggestedDriverName(previousSlave)) {
      patch.driver_name = suggestedDriverName(nextSlave);
    }

    update(patch);
  };

  return (
    <Shell
      title={state.title}
      subtitle={state.description}
      toolbar={
        <Button onClick={() => ctx.pushEvent("refresh_slaves", {})}>
          {state.capture.scan_status === "scanning" ? "Scanning..." : "Scan bus"}
        </Button>
      }
    >
      <Stack>
        <Panel title="Bus Setup">
          <Stack compact>
            <BusSetupSummary
              items={[
                { label: "Transport", value: transportLabel(busState.transport) },
                { label: "Source", value: transportSourceLabel(busState) },
                { label: "Master state", value: state.capture.master_state },
                { label: "Scan status", value: state.capture.scan_status },
              ]}
            />

            <BusSetupFields
              state={busState}
              udpPortInput={udpPortInput}
              onUdpPortInputChange={setUdpPortInput}
              onUdpPortCommit={commitUdpPort}
              onLocalPatch={(patch) =>
                setValues((previous) => ({ ...previous, transport_mode: "manual", ...patch }))
              }
              onPatch={(patch) => update({ transport_mode: "manual", ...patch })}
            />

            {state.capture.error ? <MessageLine tone="error">{state.capture.error}</MessageLine> : null}
          </Stack>
        </Panel>

        <Panel title="Select Slave">
          <Stack compact>
            {inventory.length ? (
              <DataTable headers={["", "Name", "Station", "Vendor", "Product", "AL state", "CoE"]}>
                {inventory.map((slave) => {
                  const selected = slave.value === selectedSlave;

                  return (
                    <tr key={slave.value} onClick={() => selectSlave(slave.value)}>
                      <td>
                        <input
                          type="radio"
                          name={slaveSelectionName}
                          checked={selected}
                          onChange={() => selectSlave(slave.value)}
                          aria-label={`Select ${slave.value}`}
                        />
                      </td>
                      <td>{slave.value}</td>
                      <td>{formatHex(slave.station, 4)}</td>
                      <td>{formatHex(slave.vendor_id, 8)}</td>
                      <td>{formatHex(slave.product_code, 8)}</td>
                      <td>{String(slave.al_state ?? "unknown")}</td>
                      <td>{slave.coe ? "yes" : "no"}</td>
                    </tr>
                  );
                })}
              </DataTable>
            ) : (
              <EmptyState>Scan the bus to populate the current slave list.</EmptyState>
            )}

            <MessageLine tone={selectedSlave ? "info" : "warning"}>
              {selectedSlave
                ? `Selected slave: ${selectedSlave}`
                : "Pick one discovered slave to configure scaffolding and inspect it live."}
            </MessageLine>
          </Stack>
        </Panel>

        <Tabs defaultActiveTab="Configuration">
          <Tab title="Configuration">
            <ConfigurationTab state={state} values={values} update={update} />
          </Tab>
          <Tab title="Inspection">
            <InspectionTab ctx={ctx} state={state} values={values} update={update} selectedSlave={selectedSlave} />
          </Tab>
        </Tabs>
      </Stack>
    </Shell>
  );
}

function BufferedInput({ value, onCommit, ...props }) {
  const [draft, setDraft] = useState(value ?? "");

  useEffect(() => {
    setDraft(value ?? "");
  }, [value]);

  const commit = () => {
    const nextValue = draft ?? "";

    if (nextValue !== (value ?? "")) {
      onCommit(nextValue);
    }
  };

  return (
    <Input
      {...props}
      value={draft}
      onChange={(event) => setDraft(event.target.value)}
      onBlur={commit}
      onKeyDown={(event) => {
        if (event.key === "Enter") {
          event.currentTarget.blur();
        }
      }}
    />
  );
}

function BufferedTextArea({ value, onCommit, ...props }) {
  const [draft, setDraft] = useState(value ?? "");

  useEffect(() => {
    setDraft(value ?? "");
  }, [value]);

  const commit = () => {
    const nextValue = draft ?? "";

    if (nextValue !== (value ?? "")) {
      onCommit(nextValue);
    }
  };

  return <TextArea {...props} value={draft} onChange={(event) => setDraft(event.target.value)} onBlur={commit} />;
}

function ConfigurationTab({ state, values, update }) {
  const driverName = values.driver_name ?? state.scaffold.driver_name ?? "";

  return (
    <Stack>
      <Panel title="Scaffold">
        <Stack compact>
          <div className="ke95-grid ke95-grid--2">
            <ControlField
              label="Driver Name"
              help="Generated modules are derived as EtherCAT.Drivers.<name> and EtherCAT.Drivers.<name>.Simulator."
            >
              <BufferedInput className="ke95-fill" value={driverName} onCommit={(driver_name) => update({ driver_name })} />
            </ControlField>

            <PropertyList
              items={[
                { label: "Driver Module", value: state.scaffold.driver_module ?? "n/a" },
                { label: "Simulator Module", value: state.scaffold.simulator_module ?? "n/a" },
              ]}
            />
          </div>

          <ControlField label="SDOs" help="Optional object entries to include in the capture and scaffold.">
            <BufferedTextArea
              className="ke95-fill"
              rows={4}
              placeholder="0x1008:0x00&#10;0x1009:0x00"
              value={values.capture_sdos ?? state.scaffold.capture_sdos ?? ""}
              onCommit={(capture_sdos) => update({ capture_sdos })}
            />
          </ControlField>
        </Stack>
      </Panel>

      <Panel title="PDO Naming">
        {state.capture.signal_entries?.length ? (
          <div className="ke95-grid ke95-grid--2">
            {state.capture.signal_entries.map((entry) => {
              const fieldName = `capture_signal_name::${entry.key}`;

              return (
                <ControlField
                  key={entry.key}
                  label={entry.default_name}
                  help={`${entry.direction} • PDO 0x${entry.pdo_index.toString(16).toUpperCase()} • ${entry.bit_size} bit`}
                >
                  <BufferedInput
                    className="ke95-fill"
                    value={values[fieldName] ?? entry.name}
                    onCommit={(nextValue) => update({ [fieldName]: nextValue })}
                  />
                </ControlField>
              );
            })}
          </div>
        ) : (
          <EmptyState>Pick a slave to rename the discovered PDO-derived signals.</EmptyState>
        )}
      </Panel>
    </Stack>
  );
}

function InspectionTab({ ctx, state, values, update, selectedSlave }) {
  return (
    <Stack>
      <SectionsArea sections={state.capture.sections ?? []} />

      <Panel title="Live Inspection">
      <Stack>
        <Panel
          title="ESC Registers"
          actions={
            <Button disabled={!selectedSlave} onClick={() => ctx.pushEvent("run_register", {})}>
              {selectedSlave ? "Run" : "Pick slave first"}
            </Button>
          }
        >
          <div className="ke95-grid ke95-grid--2">
            <ControlField label="Operation">
              <Dropdown
                className="ke95-fill"
                value={values.operation ?? state.inspection.register.operation}
                onChange={(event) => update({ operation: event.target.value })}
              >
                <option value="read">Read</option>
                <option value="write">Write</option>
              </Dropdown>
            </ControlField>

            <ControlField label="Addressing">
              <Dropdown
                className="ke95-fill"
                value={values.register_mode ?? state.inspection.register.register_mode}
                onChange={(event) => update({ register_mode: event.target.value })}
              >
                <option value="preset">Preset</option>
                <option value="raw">Raw</option>
              </Dropdown>
            </ControlField>

            {String(values.register_mode ?? state.inspection.register.register_mode) === "preset" ? (
              <ControlField label="Preset">
                <BufferedInput
                  className="ke95-fill"
                  value={values.register ?? state.inspection.register.register}
                  onCommit={(register) => update({ register })}
                />
              </ControlField>
            ) : (
              <>
                <ControlField label="Address">
                  <BufferedInput
                    className="ke95-fill"
                    value={values.address ?? state.inspection.register.address}
                    onCommit={(address) => update({ address })}
                  />
                </ControlField>
                <ControlField label="Size">
                  <BufferedInput
                    className="ke95-fill"
                    value={values.size ?? state.inspection.register.size}
                    onCommit={(size) => update({ size })}
                  />
                </ControlField>
              </>
            )}

            <ControlField label="Channel">
              <BufferedInput
                className="ke95-fill"
                value={values.channel ?? state.inspection.register.channel}
                onCommit={(channel) => update({ channel })}
              />
            </ControlField>

            {String(values.operation ?? state.inspection.register.operation) === "write" ? (
              <>
                {String(values.register_mode ?? state.inspection.register.register_mode) === "preset" ? (
                  <ControlField label="Value">
                    <BufferedInput
                      className="ke95-fill"
                      value={values.value ?? state.inspection.register.value}
                      onCommit={(value) => update({ value })}
                    />
                  </ControlField>
                ) : (
                  <ControlField label="Write Data">
                    <BufferedTextArea
                      className="ke95-fill"
                      rows={4}
                      value={values.write_data ?? state.inspection.register.write_data}
                      onCommit={(write_data) => update({ write_data })}
                    />
                  </ControlField>
                )}
              </>
            ) : null}
          </div>
        </Panel>

        <Panel
          title="CoE SDO"
          actions={
            <Button disabled={!selectedSlave} onClick={() => ctx.pushEvent("run_sdo", {})}>
              {selectedSlave ? "Run" : "Pick slave first"}
            </Button>
          }
        >
          <div className="ke95-grid ke95-grid--2">
            <ControlField label="Operation">
              <Dropdown
                className="ke95-fill"
                value={values.sdo_operation ?? state.inspection.sdo.operation}
                onChange={(event) => update({ sdo_operation: event.target.value })}
              >
                <option value="upload">Upload</option>
                <option value="download">Download</option>
              </Dropdown>
            </ControlField>

            <ControlField label="Index">
              <BufferedInput
                className="ke95-fill"
                value={values.sdo_index ?? state.inspection.sdo.index}
                onCommit={(sdo_index) => update({ sdo_index })}
              />
            </ControlField>

            <ControlField label="Subindex">
              <BufferedInput
                className="ke95-fill"
                value={values.sdo_subindex ?? state.inspection.sdo.subindex}
                onCommit={(sdo_subindex) => update({ sdo_subindex })}
              />
            </ControlField>

            {String(values.sdo_operation ?? state.inspection.sdo.operation) === "download" ? (
              <ControlField label="Write Data">
                <BufferedTextArea
                  className="ke95-fill"
                  rows={4}
                  value={values.sdo_write_data ?? state.inspection.sdo.write_data}
                  onCommit={(sdo_write_data) => update({ sdo_write_data })}
                />
              </ControlField>
            ) : null}
          </div>
        </Panel>

        <Panel
          title="SII EEPROM"
          actions={
            <Button disabled={!selectedSlave} onClick={() => ctx.pushEvent("run_sii", {})}>
              {selectedSlave ? "Run" : "Pick slave first"}
            </Button>
          }
        >
          <div className="ke95-grid ke95-grid--2">
            <ControlField label="Operation">
              <Dropdown
                className="ke95-fill"
                value={values.sii_operation ?? state.inspection.sii.operation}
                onChange={(event) => update({ sii_operation: event.target.value })}
              >
                <option value="identity">Identity</option>
                <option value="mailbox">Mailbox</option>
                <option value="sync_managers">Sync managers</option>
                <option value="pdo_configs">PDO configs</option>
                <option value="read_words">Read words</option>
                <option value="write_words">Write words</option>
                <option value="dump">Dump EEPROM</option>
                <option value="reload">Reload ESC</option>
              </Dropdown>
            </ControlField>

            {["read_words", "write_words"].includes(String(values.sii_operation ?? state.inspection.sii.operation)) ? (
              <>
                <ControlField label="Word Address">
                  <BufferedInput
                    className="ke95-fill"
                    value={values.sii_word_address ?? state.inspection.sii.word_address}
                    onCommit={(sii_word_address) => update({ sii_word_address })}
                  />
                </ControlField>

                {String(values.sii_operation ?? state.inspection.sii.operation) === "read_words" ? (
                  <ControlField label="Word Count">
                    <BufferedInput
                      className="ke95-fill"
                      value={values.sii_word_count ?? state.inspection.sii.word_count}
                      onCommit={(sii_word_count) => update({ sii_word_count })}
                    />
                  </ControlField>
                ) : (
                  <ControlField label="Write Data">
                    <BufferedTextArea
                      className="ke95-fill"
                      rows={4}
                      value={values.sii_write_data ?? state.inspection.sii.write_data}
                      onCommit={(sii_write_data) => update({ sii_write_data })}
                    />
                  </ControlField>
                )}
              </>
            ) : null}
          </div>
        </Panel>

        <SectionsArea sections={state.inspection.sections ?? []} />
      </Stack>
      </Panel>
    </Stack>
  );
}

function SectionsArea({ sections }) {
  if (!sections?.length) {
    return null;
  }

  return sections.map((section, index) => (
    <SectionBlock key={`${section.title ?? section.type}-${index}`} section={section} />
  ));
}

function SectionBlock({ section }) {
  if (section.type === "message") {
    return (
      <Panel title={section.title ?? "Status"}>
        <MessageLine tone={section.tone ?? "info"}>{section.text}</MessageLine>
      </Panel>
    );
  }

  if (section.type === "properties") {
    return (
      <Panel title={section.title}>
        {section.items?.length ? <PropertyList items={section.items} /> : <EmptyState>No details available.</EmptyState>}
      </Panel>
    );
  }

  if (section.type === "list") {
    return (
      <Panel title={section.title}>
        {section.items?.length ? (
          <ul>
            {section.items.map((item, index) => (
              <li key={`${item}-${index}`}>{item}</li>
            ))}
          </ul>
        ) : (
          <EmptyState>Nothing to show.</EmptyState>
        )}
      </Panel>
    );
  }

  if (section.type === "table") {
    return (
      <Panel title={section.title}>
        {section.rows?.length ? (
          <DataTable headers={section.headers ?? []}>
            {section.rows.map((row, rowIndex) => (
              <tr key={rowIndex}>
                {row.map((cell, cellIndex) => (
                  <td key={cellIndex}>{cell}</td>
                ))}
              </tr>
            ))}
          </DataTable>
        ) : (
          <EmptyState>No rows available.</EmptyState>
        )}
      </Panel>
    );
  }

  return null;
}

function suggestedDriverName(slave) {
  return camelizeSlave(slave);
}

function camelizeSlave(slave) {
  const value = String(slave ?? "").trim();

  if (!value) {
    return "Device";
  }

  const parts = value.match(/[A-Za-z0-9]+/g) ?? [];

  if (!parts.length) {
    return "Device";
  }

  return parts.map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join("");
}

function formatHex(value, pad = 4) {
  if (value == null) return "n/a";
  return "0x" + (value >>> 0).toString(16).toUpperCase().padStart(pad, "0");
}
