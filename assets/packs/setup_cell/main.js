import "./main.css";

import React, { startTransition, useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";

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
    interface: state.interface,
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
    cycle_time_us: 10000,
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

function StateBadge({ state }) {
  return <span className={`ke-setup__state ke-setup__state--${state ?? "idle"}`}>{state ?? "idle"}</span>;
}

function Section({ title, eyebrow, children, actions = null }) {
  return (
    <section className="ke-setup__section">
      <div className="ke-setup__section-header">
        <div>
          <div className="ke-setup__eyebrow">{eyebrow}</div>
          <h3 className="ke-setup__section-title">{title}</h3>
        </div>
        {actions}
      </div>
      {children}
    </section>
  );
}

function DomainCard({ domain, index, canRemove, onChange, onCommit, onRemove }) {
  return (
    <div className="ke-setup__domain-card">
      <div className="ke-setup__domain-card-header">
        <div className="ke-setup__domain-name">Domain {index + 1}</div>
        {canRemove && (
          <button type="button" className="ke-setup__ghost-button" onClick={onRemove}>
            Remove
          </button>
        )}
      </div>

      <div className="ke-setup__domain-grid">
        <label className="ke-setup__field">
          <span className="ke-setup__label">ID</span>
          <input
            className="ke-setup__input"
            value={domain.id}
            onChange={(event) => onChange({ id: event.target.value })}
            onBlur={(event) => onCommit({ id: event.target.value })}
          />
        </label>

        <label className="ke-setup__field">
          <span className="ke-setup__label">Cycle Time (us)</span>
          <input
            className="ke-setup__input"
            type="number"
            min="1000"
            step="1000"
            value={domain.cycle_time_us}
            onChange={(event) => onChange({ cycle_time_us: Number(event.target.value) || 10000 })}
            onBlur={(event) => onCommit({ cycle_time_us: Number(event.target.value) || 10000 })}
          />
        </label>

        <label className="ke-setup__field">
          <span className="ke-setup__label">Miss Threshold</span>
          <input
            className="ke-setup__input"
            type="number"
            min="1"
            step="1"
            value={domain.miss_threshold}
            onChange={(event) => onChange({ miss_threshold: Number(event.target.value) || 1 })}
            onBlur={(event) => onCommit({ miss_threshold: Number(event.target.value) || 1 })}
          />
        </label>
      </div>
    </div>
  );
}

function SlaveRow({ slave, index, domains, availableDrivers, updateLocal, commit }) {
  const selectValue = driverSelectValue(slave, availableDrivers);

  return (
    <tr>
      <td className="ke-setup__mono">{toHex(slave.station)}</td>
      <td className="ke-setup__identity">
        <div>VID {toHex(slave.vendor_id, 8)}</div>
        <div>PID {toHex(slave.product_code, 8)}</div>
      </td>
      <td>
        <input
          className="ke-setup__input"
          value={slave.name}
          onChange={(event) => updateLocal(index, { name: event.target.value })}
          onBlur={(event) => commit(index, { name: event.target.value })}
        />
      </td>
      <td className="ke-setup__muted">{slave.discovered_name || "—"}</td>
      <td>
        <select
          className="ke-setup__input"
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
        </select>

        {selectValue === CUSTOM && (
          <input
            className="ke-setup__input ke-setup__input--stacked"
            value={slave.driver}
            placeholder="MyApp.Driver.Module"
            onChange={(event) => updateLocal(index, { driver: event.target.value })}
            onBlur={(event) => commit(index, { driver: event.target.value })}
          />
        )}
      </td>
      <td>
        <select
          className="ke-setup__input"
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
        </select>
      </td>
    </tr>
  );
}

function SetupCell({ ctx, data }) {
  const [state, setState] = useState(data);
  const stateRef = useRef(state);

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

  const pushUpdate = (nextState) => {
    setState(nextState);
    ctx.pushEvent("update", serialize(nextState));
  };

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

  return (
    <div className="ke-setup">
      <section className="ke-setup__hero">
        <div className="ke-setup__hero-copy">
          <div className="ke-setup__eyebrow">EtherCAT Setup</div>
          <h2 className="ke-setup__title">Master configuration</h2>
          <p className="ke-setup__description">
            Scan the bus, map discovered slaves to drivers and PDO domains, then persist the result as
            a single static <code>EtherCAT.start/1</code> call. The generated cell ends with master and
            diagnostics tabs for the running session.
          </p>
        </div>

        <div className="ke-setup__status-panel">
          <div className="ke-setup__status-row">
            <span className="ke-setup__status-label">State</span>
            <StateBadge state={state.master_state} />
          </div>
          <div className="ke-setup__status-row">
            <span className="ke-setup__status-label">Master PID</span>
            <span className="ke-setup__mono">{state.master_pid ?? "not running"}</span>
          </div>
          <div className="ke-setup__status-row">
            <span className="ke-setup__status-label">Scan state</span>
            <span className="ke-setup__mono">{state.status}</span>
          </div>
        </div>
      </section>

      <div className="ke-setup__toolbar">
        <label className="ke-setup__field ke-setup__field--toolbar">
          <span className="ke-setup__label">Interface</span>
          <input
            className="ke-setup__input"
            value={state.interface}
            onChange={(event) => updateLocal((previous) => ({ ...previous, interface: event.target.value }))}
            onBlur={(event) => commit((previous) => ({ ...previous, interface: event.target.value }))}
          />
        </label>

        <div className="ke-setup__toolbar-actions">
          <button
            type="button"
            className="ke-setup__button ke-setup__button--primary"
            disabled={state.status === "scanning"}
            onClick={() => {
              setState((previous) => ({ ...previous, status: "scanning", error: null }));
              ctx.pushEvent("scan", {});
            }}
          >
            {hasDiscovery ? "Re-scan Bus" : "Scan Bus"}
          </button>
          <button
            type="button"
            className="ke-setup__button ke-setup__button--secondary"
            onClick={() => ctx.pushEvent("stop", {})}
          >
            Stop Master
          </button>
        </div>
      </div>

      {state.error && <div className="ke-setup__error">{state.error}</div>}

      <div className="ke-setup__grid">
        <Section
          eyebrow="PDO"
          title="Domains"
          actions={
            <button type="button" className="ke-setup__button ke-setup__button--secondary" onClick={addDomain}>
              Add Domain
            </button>
          }
        >
          <div className="ke-setup__domains">
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
        </Section>

        <Section eyebrow="Sync" title="Distributed clocks">
          <div className="ke-setup__dc-grid">
            <label className="ke-setup__toggle">
              <input
                type="checkbox"
                checked={state.dc_enabled}
                onChange={(event) => commit((previous) => ({ ...previous, dc_enabled: event.target.checked }))}
              />
              <span>Enable DC runtime</span>
            </label>

            <label className="ke-setup__field">
              <span className="ke-setup__label">Cycle (ns)</span>
              <input
                className="ke-setup__input"
                type="number"
                min="1000000"
                step="1000000"
                disabled={!state.dc_enabled}
                value={state.dc_cycle_ns}
                onChange={(event) =>
                  updateLocal((previous) => ({ ...previous, dc_cycle_ns: Number(event.target.value) || 10000000 }))
                }
                onBlur={(event) =>
                  commit((previous) => ({ ...previous, dc_cycle_ns: Number(event.target.value) || 10000000 }))
                }
              />
            </label>

            <label className="ke-setup__toggle">
              <input
                type="checkbox"
                checked={state.await_lock}
                disabled={!state.dc_enabled}
                onChange={(event) => commit((previous) => ({ ...previous, await_lock: event.target.checked }))}
              />
              <span>Gate startup on lock</span>
            </label>

            <label className="ke-setup__field">
              <span className="ke-setup__label">Lock Threshold (ns)</span>
              <input
                className="ke-setup__input"
                type="number"
                min="1"
                step="1"
                disabled={!state.dc_enabled}
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
            </label>

            <label className="ke-setup__field">
              <span className="ke-setup__label">Lock Timeout (ms)</span>
              <input
                className="ke-setup__input"
                type="number"
                min="1"
                step="1"
                disabled={!state.dc_enabled}
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
            </label>

            <label className="ke-setup__field">
              <span className="ke-setup__label">Warmup Cycles</span>
              <input
                className="ke-setup__input"
                type="number"
                min="0"
                step="1"
                disabled={!state.dc_enabled}
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
            </label>
          </div>
        </Section>
      </div>

      <Section eyebrow="Bus" title="Slave inventory">
        {hasDiscovery ? (
          <div className="ke-setup__table-wrap">
            <table className="ke-setup__table">
              <thead>
                <tr>
                  <th>Station</th>
                  <th>Identity</th>
                  <th>Name</th>
                  <th>Discovered</th>
                  <th>Driver</th>
                  <th>Domain</th>
                </tr>
              </thead>
              <tbody>
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
              </tbody>
            </table>
          </div>
        ) : (
          <div className="ke-setup__empty">
            Scan the bus to discover slaves and assign each driven device to a PDO domain.
          </div>
        )}
      </Section>
    </div>
  );
}
