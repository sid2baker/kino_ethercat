import "./main.css";

import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

export async function init(ctx, data) {
  await ctx.importCSS("main.css");
  const root = createRoot(ctx.root);
  root.render(<StartCell ctx={ctx} data={data} />);
}

function toHex(n, pad = 4) {
  return "0x" + (n >>> 0).toString(16).toUpperCase().padStart(pad, "0");
}

// ── Slave row with local edit state ──────────────────────────────────────────

const CUSTOM = "__custom__";

function SlaveRow({ slave, index, availableDrivers, onUpdate }) {
  const [name, setName] = useState(slave.name);
  const [driver, setDriver] = useState(slave.driver);

  const knownModules = availableDrivers.map((d) => d.module);
  const isKnown = driver === "" || knownModules.includes(driver);
  const selectValue = isKnown ? driver : CUSTOM;

  useEffect(() => {
    setName(slave.name);
    setDriver(slave.driver);
  }, [slave.name, slave.driver]);

  const commit = (nextDriver) => onUpdate(index, name, nextDriver);
  const commitName = () => onUpdate(index, name, driver);

  const handleSelectChange = (e) => {
    const val = e.target.value;
    if (val === CUSTOM) {
      setDriver("");
    } else {
      setDriver(val);
      onUpdate(index, name, val);
    }
  };

  return (
    <tr className="border-t border-gray-200">
      <td className="py-1 pr-4 text-gray-500 font-mono">{toHex(slave.station)}</td>
      <td className="py-1 pr-4 text-gray-400 font-mono text-xs">
        <div>VID {toHex(slave.vendor_id, 8)}</div>
        <div>PID {toHex(slave.product_code, 8)}</div>
      </td>
      <td className="py-1 pr-2">
        <input
          className="w-32 border border-gray-300 rounded px-2 py-0.5 font-mono text-sm focus:outline-none focus:border-blue-400"
          value={name}
          onChange={(e) => setName(e.target.value)}
          onBlur={commitName}
          onKeyDown={(e) => e.key === "Enter" && commitName()}
          placeholder="slave_name"
        />
      </td>
      <td className="py-1 pr-4 text-gray-400 font-mono text-xs">
        {slave.discovered_name ?? "—"}
      </td>
      <td className="py-1">
        <div className="flex flex-col gap-1">
          <select
            className="border border-gray-300 rounded px-2 py-0.5 font-mono text-sm focus:outline-none focus:border-blue-400 text-gray-700 bg-white"
            value={selectValue}
            onChange={handleSelectChange}
          >
            <option value="">— none —</option>
            {availableDrivers.map((d) => (
              <option key={d.module} value={d.module}>
                {d.name}
              </option>
            ))}
            <option value={CUSTOM}>Custom…</option>
          </select>
          {selectValue === CUSTOM && (
            <input
              className="w-48 border border-gray-300 rounded px-2 py-0.5 font-mono text-sm focus:outline-none focus:border-blue-400 text-gray-500"
              value={driver}
              onChange={(e) => setDriver(e.target.value)}
              onBlur={() => commit(driver)}
              onKeyDown={(e) => e.key === "Enter" && commit(driver)}
              placeholder="MyApp.MyDriver"
              autoFocus
            />
          )}
        </div>
      </td>
    </tr>
  );
}

// ── Runtime config row ────────────────────────────────────────────────────────

function RuntimeConfig({
  backupInterface,
  domainId,
  cycleTimeUs,
  activationMode,
  dcEnabled,
  awaitLock,
  lockThresholdNs,
  lockTimeoutMs,
  onChange,
}) {
  const [backup, setBackup] = useState(backupInterface);
  const [id, setId] = useState(domainId);
  const [cycle, setCycle] = useState(cycleTimeUs);
  const [activation, setActivation] = useState(activationMode);
  const [dc, setDc] = useState(dcEnabled);
  const [lockGate, setLockGate] = useState(awaitLock);
  const [threshold, setThreshold] = useState(lockThresholdNs);
  const [timeout, setTimeoutMs] = useState(lockTimeoutMs);

  const push = (overrides = {}) =>
    onChange({
      backup_interface: backup,
      domain_id: id,
      cycle_time_us: Number(cycle),
      activation_mode: activation,
      "dc_enabled?": dc,
      "await_lock?": lockGate,
      lock_threshold_ns: Number(threshold),
      lock_timeout_ms: Number(timeout),
      ...overrides,
    });

  return (
    <div className="space-y-2 pt-2 border-t border-gray-200 text-sm text-gray-600">
      <div className="font-semibold text-gray-700">Runtime</div>
      <div className="flex flex-wrap items-center gap-4">
        <label className="flex items-center gap-1">
          <span>backup:</span>
          <input
            className="w-28 border border-gray-300 rounded px-2 py-0.5 font-mono focus:outline-none focus:border-blue-400"
            value={backup}
            onChange={(e) => setBackup(e.target.value)}
            onBlur={() => push()}
            onKeyDown={(e) => e.key === "Enter" && push()}
            placeholder="optional"
          />
        </label>
        <label className="flex items-center gap-1">
          <span>domain:</span>
          <input
            className="w-24 border border-gray-300 rounded px-2 py-0.5 font-mono focus:outline-none focus:border-blue-400"
            value={id}
            onChange={(e) => setId(e.target.value)}
            onBlur={() => push()}
            onKeyDown={(e) => e.key === "Enter" && push()}
          />
        </label>
        <label className="flex items-center gap-1">
          <span>cycle_time_us:</span>
          <input
            type="number"
            min="1000"
            step="1000"
            className="w-24 border border-gray-300 rounded px-2 py-0.5 font-mono focus:outline-none focus:border-blue-400"
            value={cycle}
            onChange={(e) => setCycle(Number(e.target.value))}
            onBlur={() => push()}
            onKeyDown={(e) => e.key === "Enter" && push()}
          />
        </label>
        <label className="flex items-center gap-1">
          <span>target:</span>
          <select
            className="border border-gray-300 rounded px-2 py-0.5 font-mono text-sm focus:outline-none focus:border-blue-400 text-gray-700 bg-white"
            value={activation}
            onChange={(e) => {
              setActivation(e.target.value);
              push({ activation_mode: e.target.value });
            }}
          >
            <option value="op">operational</option>
            <option value="preop">pre-op only</option>
          </select>
        </label>
      </div>
      <div className="flex flex-wrap items-center gap-4 text-xs text-gray-500">
        <label className="flex items-center gap-1.5">
          <input
            type="checkbox"
            checked={dc}
            onChange={(e) => {
              setDc(e.target.checked);
              push({ "dc_enabled?": e.target.checked });
            }}
          />
          <span>Enable DC</span>
        </label>
        <label className="flex items-center gap-1.5">
          <input
            type="checkbox"
            checked={lockGate}
            disabled={!dc}
            onChange={(e) => {
              setLockGate(e.target.checked);
              push({ "await_lock?": e.target.checked });
            }}
          />
          <span>Await lock</span>
        </label>
        <label className="flex items-center gap-1">
          <span>lock_threshold_ns:</span>
          <input
            type="number"
            min="1"
            className="w-20 border border-gray-300 rounded px-2 py-0.5 font-mono focus:outline-none focus:border-blue-400 disabled:bg-gray-50"
            value={threshold}
            disabled={!dc}
            onChange={(e) => setThreshold(Number(e.target.value))}
            onBlur={() => push()}
            onKeyDown={(e) => e.key === "Enter" && push()}
          />
        </label>
        <label className="flex items-center gap-1">
          <span>lock_timeout_ms:</span>
          <input
            type="number"
            min="1"
            className="w-20 border border-gray-300 rounded px-2 py-0.5 font-mono focus:outline-none focus:border-blue-400 disabled:bg-gray-50"
            value={timeout}
            disabled={!dc}
            onChange={(e) => setTimeoutMs(Number(e.target.value))}
            onBlur={() => push()}
            onKeyDown={(e) => e.key === "Enter" && push()}
          />
        </label>
      </div>
    </div>
  );
}

// ── Main component ────────────────────────────────────────────────────────────

const PHASE_STYLES = {
  idle: { dot: "bg-gray-400", label: "text-gray-500", text: "idle" },
  scanning: { dot: "bg-blue-400 animate-pulse", label: "text-blue-600", text: "scanning" },
  configuring: { dot: "bg-yellow-400 animate-pulse", label: "text-yellow-600", text: "configuring" },
  preop_ready: { dot: "bg-yellow-400", label: "text-yellow-600", text: "pre-op ready" },
  operational: { dot: "bg-green-500", label: "text-green-700", text: "operational" },
  degraded: { dot: "bg-red-500", label: "text-red-700", text: "degraded" },
};

function PhaseBadge({ phase }) {
  const s = PHASE_STYLES[phase] ?? PHASE_STYLES.idle;
  return (
    <div className="flex items-center gap-1.5 px-2 py-0.5 rounded-full bg-gray-100 border border-gray-200">
      <span className={`inline-block w-2 h-2 rounded-full ${s.dot}`} />
      <span className={`text-xs font-medium font-mono ${s.label}`}>{s.text}</span>
    </div>
  );
}

function StartCell({ ctx, data }) {
  const [iface, setIface] = useState(data.interface);
  const [status, setStatus] = useState(data.status);
  const [error, setError] = useState(data.error);
  const [slaves, setSlaves] = useState(data.slaves);
  const [backupInterface, setBackupInterface] = useState(data.backup_interface ?? "");
  const [domainId, setDomainId] = useState(data.domain_id);
  const [cycleTimeUs, setCycleTimeUs] = useState(data.cycle_time_us);
  const [activationMode, setActivationMode] = useState(data.activation_mode ?? "op");
  const [dcEnabled, setDcEnabled] = useState(data["dc_enabled?"] ?? true);
  const [awaitLock, setAwaitLock] = useState(data["await_lock?"] ?? false);
  const [lockThresholdNs, setLockThresholdNs] = useState(data.lock_threshold_ns ?? 100);
  const [lockTimeoutMs, setLockTimeoutMs] = useState(data.lock_timeout_ms ?? 5000);
  const [masterPhase, setMasterPhase] = useState(data.master_phase ?? "idle");
  const availableDrivers = data.available_drivers ?? [];

  useEffect(() => {
    ctx.handleEvent("status", ({ status }) => setStatus(status));
    ctx.handleEvent("scan_result", ({ slaves }) => {
      setSlaves(slaves);
      setStatus("discovered");
    });
    ctx.handleEvent("scan_error", ({ error }) => {
      setError(error);
      setStatus("error");
    });
    ctx.handleEvent("master_phase", ({ phase }) => setMasterPhase(phase));
    ctx.handleSync(() => {
      const active = document.activeElement;
      if (active instanceof HTMLElement && ctx.root.contains(active)) {
        active.blur();
      }
    });
  }, []);

  const handleScan = () => {
    setStatus("scanning");
    setError(null);
    ctx.pushEvent("scan");
  };

  const handleStop = () => ctx.pushEvent("stop");

  const handleIfaceChange = (e) => {
    setIface(e.target.value);
    ctx.pushEvent("update_interface", { interface: e.target.value });
  };

  const handleSlaveUpdate = (idx, name, driver) => {
    setSlaves((prev) => prev.map((s, i) => (i === idx ? { ...s, name, driver } : s)));
    ctx.pushEvent("update_slave", { index: idx, name, driver });
  };

  const handleRuntimeChange = (next) => {
    setBackupInterface(next.backup_interface);
    setDomainId(next.domain_id);
    setCycleTimeUs(next.cycle_time_us);
    setActivationMode(next.activation_mode);
    setDcEnabled(next["dc_enabled?"]);
    setAwaitLock(next["await_lock?"]);
    setLockThresholdNs(next.lock_threshold_ns);
    setLockTimeoutMs(next.lock_timeout_ms);
    ctx.pushEvent("update_runtime", next);
  };

  const scanning = status === "scanning";

  return (
    <div className="p-3 space-y-3 font-sans text-sm select-none">
      {/* Interface row */}
      <div className="flex items-center gap-2">
        <label className="text-gray-500 font-mono text-xs">interface</label>
        <input
          className="w-32 border border-gray-300 rounded px-2 py-1 font-mono text-sm focus:outline-none focus:border-blue-400 disabled:bg-gray-50 disabled:text-gray-400"
          value={iface}
          onChange={handleIfaceChange}
          disabled={scanning}
          placeholder="eth0"
        />
        <button
          onClick={handleScan}
          disabled={scanning}
          className="px-3 py-1 bg-blue-500 hover:bg-blue-600 active:bg-blue-700 disabled:bg-gray-300 text-white rounded text-sm font-medium transition-colors"
        >
          {status === "discovered" ? "Re-scan" : "Scan Bus"}
        </button>
        <button
          onClick={handleStop}
          className="px-3 py-1 bg-red-500 hover:bg-red-600 active:bg-red-700 text-white rounded text-sm font-medium transition-colors"
        >
          Stop
        </button>
        {scanning && (
          <span className="text-gray-400 text-xs animate-pulse">Scanning…</span>
        )}
        <div className="ml-auto">
          <PhaseBadge phase={masterPhase} />
        </div>
      </div>

      {/* Error */}
      {status === "error" && (
        <div className="text-red-600 text-xs bg-red-50 border border-red-200 rounded px-3 py-2 font-mono">
          {error}
        </div>
      )}

      {/* Slave table */}
      {status === "discovered" && slaves.length > 0 && (
        <>
          <div
            className="text-xs rounded px-3 py-2 border font-mono bg-emerald-50 border-emerald-200 text-emerald-700"
          >
            Source mode: static startup configuration. Bus discovery stays live in
            the Smart Cell, but persisted code is emitted as a single
            EtherCAT.start/1 call with the full slave config.
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-gray-400 text-xs">
                  <th className="pb-1 pr-4 font-medium">Station</th>
                  <th className="pb-1 pr-4 font-medium">Identity</th>
                  <th className="pb-1 pr-2 font-medium">Name</th>
                  <th className="pb-1 pr-4 font-medium">Discovered</th>
                  <th className="pb-1 font-medium">Driver</th>
                </tr>
              </thead>
              <tbody>
                {slaves.map((slave, idx) => (
                  <SlaveRow
                    key={idx}
                    slave={slave}
                    index={idx}
                    availableDrivers={availableDrivers}
                    onUpdate={handleSlaveUpdate}
                  />
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}

      {/* Runtime config */}
      {status === "discovered" && (
        <RuntimeConfig
          backupInterface={backupInterface}
          domainId={domainId}
          cycleTimeUs={cycleTimeUs}
          activationMode={activationMode}
          dcEnabled={dcEnabled}
          awaitLock={awaitLock}
          lockThresholdNs={lockThresholdNs}
          lockTimeoutMs={lockTimeoutMs}
          onChange={handleRuntimeChange}
        />
      )}
    </div>
  );
}
