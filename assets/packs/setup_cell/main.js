import "./main.css";

import React, { startTransition, useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";

import {
  Button,
  Checkbox,
  ControlField,
  DataTable,
  Dropdown,
  EmptyState,
  Frame,
  Input,
  MessageLine,
  Mono,
  Panel,
  Shell,
  StatusBadge,
  SummaryGrid,
} from "../../ui/react95";

const CUSTOM = "__custom__";

export async function init(ctx, data) {
  await ctx.importCSS("main.css");
  const root = createRoot(ctx.root);
  root.render(<SetupCell ctx={ctx} data={data} />);
}

function toHex(value, pad = 4) {
  return "0x" + Number(value >>> 0).toString(16).toUpperCase().padStart(pad, "0");
}

function serialize(state) {
  return {
    transport: state.transport,
    interface: state.interface,
    host: state.host,
    port: state.port,
    domains: state.domains,
    slaves: state.slaves,
    dc_enabled: state.dc_enabled,
    dc_cycle_ns: state.dc_cycle_ns,
    await_lock: state.await_lock,
    lock_threshold_ns: state.lock_threshold_ns,
    lock_timeout_ms: state.lock_timeout_ms,
    warmup_cycles: state.warmup_cycles,
  };
}

function nextDomain(domains) {
  const suffix = domains.length + 1;

  return {
    id: `domain_${suffix}`,
    cycle_time_ms: 10,
    miss_threshold: 1000,
  };
}

function applySlaveUpdate(state, index, patch) {
  const domains = state.domains.map((domain) => domain.id);

  const slaves = state.slaves.map((slave, currentIndex) => {
    if (currentIndex !== index) return slave;

    const next = { ...slave, ...patch };

    if (!next.driver) {
      return { ...next, domain_id: "" };
    }

    if (!domains.includes(next.domain_id)) {
      return { ...next, domain_id: domains[0] ?? "" };
    }

    return next;
  });

  return { ...state, slaves };
}

function applyDomainUpdate(state, index, patch) {
  const domains = state.domains.map((domain, currentIndex) => (currentIndex === index ? { ...domain, ...patch } : domain));
  const validIds = domains.map((domain) => domain.id).filter(Boolean);
  const defaultId = validIds[0] ?? "";

  const slaves = state.slaves.map((slave) => {
    if (!slave.driver) return { ...slave, domain_id: "" };
    if (validIds.includes(slave.domain_id)) return slave;
    return { ...slave, domain_id: defaultId };
  });

  return { ...state, domains, slaves };
}

function removeDomain(state, index) {
  const domains = state.domains.filter((_, currentIndex) => currentIndex !== index);
  const safeDomains = domains.length === 0 ? [nextDomain([])] : domains;
  const validIds = safeDomains.map((domain) => domain.id);
  const defaultId = validIds[0] ?? "";

  const slaves = state.slaves.map((slave) => {
    if (!slave.driver) return { ...slave, domain_id: "" };
    if (validIds.includes(slave.domain_id)) return slave;
    return { ...slave, domain_id: defaultId };
  });

  return { ...state, domains: safeDomains, slaves };
}

function knownDriverModules(availableDrivers) {
  return availableDrivers.map((driver) => driver.module);
}

function driverSelectValue(slave, availableDrivers) {
  const known = knownDriverModules(availableDrivers);
  return slave.driver === "" || known.includes(slave.driver) ? slave.driver : CUSTOM;
}

function interfaceOptions(state) {
  const options = Array.isArray(state.available_interfaces) ? [...state.available_interfaces] : [];

  if (state.interface && !options.includes(state.interface)) {
    options.unshift(state.interface);
  }

  return options;
}

function transportSourceLabel(state) {
  return state.transport === "udp"
    ? state.transport_source || "udp:unconfigured"
    : state.interface || "n/a";
}

function masterStateTone(state) {
  const value = String(state ?? "").toLowerCase();

  if (["operational", "preop_ready", "active"].includes(value)) return "ok";
  if (["discovering", "awaiting_preop", "recovering", "scanning"].includes(value)) return "warn";
  if (["activation_blocked", "error", "down"].includes(value)) return "danger";
  return "neutral";
}

function statusTone(status) {
  if (status === "scanning") return "warn";
  if (status === "error") return "danger";
  return "neutral";
}

function SetupCell({ ctx, data }) {
  const [state, setState] = useState(data);
  const [udpPortInput, setUdpPortInput] = useState(String(data.port ?? 34980));
  const stateRef = useRef(state);
  const interfaces = interfaceOptions(state);

  useEffect(() => {
    stateRef.current = state;
  }, [state]);

  useEffect(() => {
    ctx.handleEvent("snapshot", (next) => {
      startTransition(() => setState(next));
    });

    ctx.handleSync(() => {
      const active = document.activeElement;

      if (active instanceof HTMLElement && ctx.root.contains(active)) {
        active.dispatchEvent(new Event("change", { bubbles: true }));
        active.dispatchEvent(new Event("blur", { bubbles: true }));
      } else {
        ctx.pushEvent("update", serialize(stateRef.current));
      }
    });
  }, [ctx]);

  useEffect(() => {
    setUdpPortInput(String(state.port ?? 34980));
  }, [state.transport, state.port]);

  const updateLocal = (recipe) => {
    setState((previous) => recipe(previous));
  };

  const commit = (recipe) => {
    setState((previous) => {
      const nextState = recipe(previous);
      ctx.pushEvent("update", serialize(nextState));
      return nextState;
    });
  };

  const addDomain = () => {
    commit((previous) => ({
      ...previous,
      domains: [...previous.domains, nextDomain(previous.domains)],
    }));
  };

  const hasDiscovery = state.slaves.length > 0;

  const commitUdpPort = (rawValue) => {
    const trimmed = String(rawValue ?? "").trim();
    const parsed = Number.parseInt(trimmed, 10);
    const port = Number.isInteger(parsed) && parsed > 0 ? parsed : 34980;

    setUdpPortInput(String(port));
    commit((previous) => ({ ...previous, port }));
  };

  return (
    <Shell
      title="EtherCAT Setup"
      subtitle="Scan the bus, assign drivers and domains, then persist a single static EtherCAT.start/1 configuration."
      status={
        <>
          <StatusBadge tone={masterStateTone(state.master_state)}>{state.master_state ?? "idle"}</StatusBadge>
          <StatusBadge tone={statusTone(state.status)}>{state.status}</StatusBadge>
        </>
      }
      toolbar={
        <>
          <Button
            disabled={state.status === "scanning"}
            onClick={() => {
              setState((previous) => ({ ...previous, status: "scanning", error: null }));
              ctx.pushEvent("scan", {});
            }}
          >
            {hasDiscovery ? "Re-scan bus" : "Scan bus"}
          </Button>
          <Button onClick={() => ctx.pushEvent("stop", {})}>Stop master</Button>
        </>
      }
    >
      <SummaryGrid
        items={[
          { label: "Master PID", value: state.master_pid ?? "not running" },
          { label: "Transport", value: state.transport ?? "raw" },
          { label: "Bus source", value: transportSourceLabel(state) },
          { label: "Slaves", value: String(state.slaves.length) },
          { label: "Domains", value: String(state.domains.length) },
        ]}
      />

      <Panel title="Bus">
        <div className="ke95-grid ke95-grid--2">
          <ControlField label="Transport">
            <Dropdown
              className="ke95-fill"
              value={state.transport}
              onChange={(event) => commit((previous) => ({ ...previous, transport: event.target.value }))}
            >
              <option value="raw">Raw socket</option>
              <option value="udp">UDP</option>
            </Dropdown>
          </ControlField>

          {state.transport === "udp" ? (
            <>
              <ControlField label="Host">
                <Input
                  className="ke95-fill"
                  placeholder="127.0.0.2"
                  value={state.host}
                  onChange={(event) => updateLocal((previous) => ({ ...previous, host: event.target.value }))}
                  onBlur={(event) => commit((previous) => ({ ...previous, host: event.target.value }))}
                />
              </ControlField>

              <ControlField label="Port">
                <Input
                  className="ke95-fill"
                  type="number"
                  min="1"
                  step="1"
                  value={udpPortInput}
                  onChange={(event) => setUdpPortInput(event.target.value)}
                  onBlur={(event) => commitUdpPort(event.target.value)}
                  onKeyDown={(event) => event.key === "Enter" && commitUdpPort(event.target.value)}
                />
              </ControlField>
            </>
          ) : (
            <ControlField label="Interface" className="ke95-fill">
              <Dropdown
                className="ke95-fill"
                value={state.interface}
                onChange={(event) => commit((previous) => ({ ...previous, interface: event.target.value }))}
              >
                {interfaces.map((name) => (
                  <option key={name} value={name}>
                    {name}
                  </option>
                ))}
              </Dropdown>
            </ControlField>
          )}
        </div>
      </Panel>

      {state.error ? <MessageLine tone="error">{state.error}</MessageLine> : null}

      <div className="ke95-grid ke95-grid--2">
        <Panel
          title="Domains"
          actions={<Button onClick={addDomain}>Add domain</Button>}
        >
          <div className="ke95-grid">
            {state.domains.map((domain, index) => (
              <DomainCard
                key={`domain-${index}`}
                domain={domain}
                index={index}
                canRemove={state.domains.length > 1}
                onChange={(patch) => updateLocal((previous) => applyDomainUpdate(previous, index, patch))}
                onCommit={(patch) => commit((previous) => applyDomainUpdate(previous, index, patch))}
                onRemove={() => commit((previous) => removeDomain(previous, index))}
              />
            ))}
          </div>
        </Panel>

        <Panel title="Distributed clocks">
          <div className="ke95-grid ke95-grid--2">
            <Checkbox
              checked={state.dc_enabled}
              label="Enable DC runtime"
              onChange={(event) => commit((previous) => ({ ...previous, dc_enabled: event.target.checked }))}
            />

            <Checkbox
              checked={state.await_lock}
              disabled={!state.dc_enabled}
              label="Gate startup on lock"
              onChange={(event) => commit((previous) => ({ ...previous, await_lock: event.target.checked }))}
            />

            <ControlField label="Cycle (ns)">
              <Input
                type="number"
                min="1000000"
                step="1000000"
                disabled={!state.dc_enabled}
                className="ke95-fill"
                value={state.dc_cycle_ns}
                onChange={(event) =>
                  updateLocal((previous) => ({ ...previous, dc_cycle_ns: Number(event.target.value) || 10000000 }))
                }
                onBlur={(event) =>
                  commit((previous) => ({ ...previous, dc_cycle_ns: Number(event.target.value) || 10000000 }))
                }
              />
            </ControlField>

            <ControlField label="Lock threshold (ns)">
              <Input
                type="number"
                min="1"
                step="1"
                disabled={!state.dc_enabled}
                className="ke95-fill"
                value={state.lock_threshold_ns}
                onChange={(event) =>
                  updateLocal((previous) => ({
                    ...previous,
                    lock_threshold_ns: Number(event.target.value) || 1,
                  }))
                }
                onBlur={(event) =>
                  commit((previous) => ({
                    ...previous,
                    lock_threshold_ns: Number(event.target.value) || 1,
                  }))
                }
              />
            </ControlField>

            <ControlField label="Lock timeout (ms)">
              <Input
                type="number"
                min="1"
                step="1"
                disabled={!state.dc_enabled}
                className="ke95-fill"
                value={state.lock_timeout_ms}
                onChange={(event) =>
                  updateLocal((previous) => ({
                    ...previous,
                    lock_timeout_ms: Number(event.target.value) || 1,
                  }))
                }
                onBlur={(event) =>
                  commit((previous) => ({
                    ...previous,
                    lock_timeout_ms: Number(event.target.value) || 1,
                  }))
                }
              />
            </ControlField>

            <ControlField label="Warmup cycles">
              <Input
                type="number"
                min="0"
                step="1"
                disabled={!state.dc_enabled}
                className="ke95-fill"
                value={state.warmup_cycles}
                onChange={(event) =>
                  updateLocal((previous) => ({
                    ...previous,
                    warmup_cycles: Number(event.target.value) || 0,
                  }))
                }
                onBlur={(event) =>
                  commit((previous) => ({
                    ...previous,
                    warmup_cycles: Number(event.target.value) || 0,
                  }))
                }
              />
            </ControlField>
          </div>
        </Panel>
      </div>

      <Panel title="Slave inventory">
        {hasDiscovery ? (
          <DataTable headers={["Station", "Identity", "Name", "Discovered", "Driver", "Domain"]}>
            {state.slaves.map((slave, index) => (
              <SlaveRow
                key={`${slave.discovered_name}-${index}`}
                slave={slave}
                index={index}
                domains={state.domains}
                availableDrivers={state.available_drivers}
                updateLocal={(rowIndex, patch) =>
                  updateLocal((previous) => applySlaveUpdate(previous, rowIndex, patch))
                }
                commit={(rowIndex, patch) => commit((previous) => applySlaveUpdate(previous, rowIndex, patch))}
              />
            ))}
          </DataTable>
        ) : (
          <EmptyState>Scan the bus to discover slaves and assign each driven device to a PDO domain.</EmptyState>
        )}
      </Panel>
    </Shell>
  );
}

function DomainCard({ domain, index, canRemove, onChange, onCommit, onRemove }) {
  return (
    <Frame boxShadow="in" className="ke95-setup__domain-card">
      <div className="ke95-toolbar">
        <div className="ke95-kicker">Domain {index + 1}</div>
        {canRemove ? <Button onClick={onRemove}>Remove</Button> : null}
      </div>

      <div className="ke95-grid ke95-grid--3">
        <ControlField label="ID">
          <Input
            className="ke95-fill"
            value={domain.id}
            onChange={(event) => onChange({ id: event.target.value })}
            onBlur={(event) => onCommit({ id: event.target.value })}
          />
        </ControlField>

        <ControlField label="Cycle time (ms)">
          <Input
            className="ke95-fill"
            type="number"
            min="1"
            step="1"
            value={domain.cycle_time_ms}
            onChange={(event) => onChange({ cycle_time_ms: Number(event.target.value) || 10 })}
            onBlur={(event) => onCommit({ cycle_time_ms: Number(event.target.value) || 10 })}
          />
        </ControlField>

        <ControlField label="Miss threshold">
          <Input
            className="ke95-fill"
            type="number"
            min="1"
            step="1"
            value={domain.miss_threshold}
            onChange={(event) => onChange({ miss_threshold: Number(event.target.value) || 1 })}
            onBlur={(event) => onCommit({ miss_threshold: Number(event.target.value) || 1 })}
          />
        </ControlField>
      </div>
    </Frame>
  );
}

function SlaveRow({ slave, index, domains, availableDrivers, updateLocal, commit }) {
  const selectValue = driverSelectValue(slave, availableDrivers);

  return (
    <tr>
      <td><Mono>{toHex(slave.station)}</Mono></td>
      <td>
        <Mono as="div">VID {toHex(slave.vendor_id, 8)}</Mono>
        <Mono as="div">PID {toHex(slave.product_code, 8)}</Mono>
      </td>
      <td>
        <Input
          className="ke95-fill"
          value={slave.name}
          onChange={(event) => updateLocal(index, { name: event.target.value })}
          onBlur={(event) => commit(index, { name: event.target.value })}
        />
      </td>
      <td><Mono>{slave.discovered_name || "—"}</Mono></td>
      <td>
        <div className="ke95-grid">
          <Dropdown
            className="ke95-fill"
            value={selectValue}
            onChange={(event) => {
              if (event.target.value === CUSTOM) {
                updateLocal(index, { driver: "" });
                return;
              }

              commit(index, { driver: event.target.value });
            }}
          >
            <option value="">No driver</option>
            {availableDrivers.map((driver) => (
              <option key={driver.module} value={driver.module}>
                {driver.name}
              </option>
            ))}
            <option value={CUSTOM}>Custom…</option>
          </Dropdown>

          {selectValue === CUSTOM ? (
            <Input
              className="ke95-fill"
              value={slave.driver}
              placeholder="MyApp.Driver.Module"
              onChange={(event) => updateLocal(index, { driver: event.target.value })}
              onBlur={(event) => commit(index, { driver: event.target.value })}
            />
          ) : null}
        </div>
      </td>
      <td>
        <Dropdown
          className="ke95-fill"
          disabled={!slave.driver}
          value={slave.domain_id || ""}
          onChange={(event) => commit(index, { domain_id: event.target.value })}
        >
          <option value="">No PDO domain</option>
          {domains.map((domain) => (
            <option key={domain.id} value={domain.id}>
              {domain.id}
            </option>
          ))}
        </Dropdown>
      </td>
    </tr>
  );
}
