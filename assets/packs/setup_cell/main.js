import "./main.css";

import React, { useEffect, useRef, useState } from "react";
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

function SlaveRow({ slave, index, onUpdate }) {
  const [name, setName] = useState(slave.name);
  const [driver, setDriver] = useState(slave.driver);

  useEffect(() => {
    setName(slave.name);
    setDriver(slave.driver);
  }, [slave.name, slave.driver]);

  const handleBlur = () => onUpdate(index, name, driver);

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
          onBlur={handleBlur}
          onKeyDown={(e) => e.key === "Enter" && handleBlur()}
          placeholder="slave_name"
        />
      </td>
      <td className="py-1">
        <input
          className="w-48 border border-gray-300 rounded px-2 py-0.5 font-mono text-sm focus:outline-none focus:border-blue-400 text-gray-500"
          value={driver}
          onChange={(e) => setDriver(e.target.value)}
          onBlur={handleBlur}
          onKeyDown={(e) => e.key === "Enter" && handleBlur()}
          placeholder="MyApp.EL1809"
        />
      </td>
    </tr>
  );
}

// ── Domain config row ─────────────────────────────────────────────────────────

function DomainConfig({ domainId, cycleTimeUs, onChange }) {
  const [id, setId] = useState(domainId);
  const [cycle, setCycle] = useState(cycleTimeUs);

  const push = () => onChange(id, Number(cycle));

  return (
    <div className="flex items-center gap-4 pt-2 border-t border-gray-200 text-sm text-gray-600">
      <span className="font-semibold text-gray-700">Domain</span>
      <label className="flex items-center gap-1">
        <span>id:</span>
        <input
          className="w-24 border border-gray-300 rounded px-2 py-0.5 font-mono focus:outline-none focus:border-blue-400"
          value={id}
          onChange={(e) => setId(e.target.value)}
          onBlur={push}
          onKeyDown={(e) => e.key === "Enter" && push()}
        />
      </label>
      <label className="flex items-center gap-1">
        <span>cycle_time_us:</span>
        <input
          type="number"
          min="100"
          className="w-24 border border-gray-300 rounded px-2 py-0.5 font-mono focus:outline-none focus:border-blue-400"
          value={cycle}
          onChange={(e) => setCycle(Number(e.target.value))}
          onBlur={push}
          onKeyDown={(e) => e.key === "Enter" && push()}
        />
      </label>
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
  const [domainId, setDomainId] = useState(data.domain_id);
  const [cycleTimeUs, setCycleTimeUs] = useState(data.cycle_time_us);
  const [masterPhase, setMasterPhase] = useState(data.master_phase ?? "idle");

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

  const handleDomainChange = (id, cycle) => {
    setDomainId(id);
    setCycleTimeUs(cycle);
    ctx.pushEvent("update_domain", { domain_id: id, cycle_time_us: cycle });
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
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-gray-400 text-xs">
                <th className="pb-1 pr-4 font-medium">Station</th>
                <th className="pb-1 pr-4 font-medium">Identity</th>
                <th className="pb-1 pr-2 font-medium">Name</th>
                <th className="pb-1 font-medium">Driver</th>
              </tr>
            </thead>
            <tbody>
              {slaves.map((slave, idx) => (
                <SlaveRow
                  key={idx}
                  slave={slave}
                  index={idx}
                  onUpdate={handleSlaveUpdate}
                />
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Domain config */}
      {status === "discovered" && (
        <DomainConfig
          domainId={domainId}
          cycleTimeUs={cycleTimeUs}
          onChange={handleDomainChange}
        />
      )}
    </div>
  );
}
