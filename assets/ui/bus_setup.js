import React from "react";

import { Columns, ControlField, Dropdown, Input, Mono } from "./react95";

export function interfaceOptions({ available_interfaces = [], interface: primary = "", backup_interface: backup = "" }) {
  const options = Array.isArray(available_interfaces) ? [...available_interfaces] : [];

  if (primary && !options.includes(primary)) {
    options.unshift(primary);
  }

  if (backup && !options.includes(backup)) {
    options.unshift(backup);
  }

  return options;
}

export function transportLabel(transport) {
  switch (transport) {
    case "raw_redundant":
      return "raw + redundant";
    case "udp":
      return "udp";
    default:
      return "raw";
  }
}

export function transportSourceLabel(state) {
  return state.transport_source || (state.transport === "udp" ? "udp:unconfigured" : state.interface || "n/a");
}

export function BusSetupFields({
  state,
  udpPortInput,
  onUdpPortInputChange,
  onUdpPortCommit,
  onPatch,
  onLocalPatch = onPatch,
  labels = {},
}) {
  const interfaces = interfaceOptions(state);
  const transportLabelText = labels.transport ?? "Transport";
  const interfaceLabel = labels.interface ?? "Interface";
  const backupInterfaceLabel = labels.backupInterface ?? "Backup interface";
  const hostLabel = labels.host ?? "Host";
  const portLabel = labels.port ?? "Port";

  return (
    <Columns minWidth="14rem">
      <ControlField label={transportLabelText}>
        <Dropdown
          className="ke95-fill"
          value={state.transport}
          onChange={(event) => onPatch({ transport: event.target.value })}
        >
          <option value="raw">Raw socket</option>
          <option value="raw_redundant">Raw + redundant</option>
          <option value="udp">UDP</option>
        </Dropdown>
      </ControlField>

      {state.transport === "udp" ? (
        <>
          <ControlField label={hostLabel}>
            <Input
              className="ke95-fill"
              placeholder="127.0.0.2"
              value={state.host}
              onChange={(event) => onLocalPatch({ host: event.target.value })}
              onBlur={(event) => onPatch({ host: event.target.value })}
            />
          </ControlField>

          <ControlField label={portLabel}>
            <Input
              className="ke95-fill"
              type="number"
              min="1"
              step="1"
              value={udpPortInput}
              onChange={(event) => onUdpPortInputChange(event.target.value)}
              onBlur={(event) => onUdpPortCommit(event.target.value)}
              onKeyDown={(event) => event.key === "Enter" && onUdpPortCommit(event.target.value)}
            />
          </ControlField>
        </>
      ) : (
        <>
          <ControlField label={interfaceLabel} className="ke95-fill">
            <Dropdown
              className="ke95-fill"
              value={state.interface}
              onChange={(event) => onPatch({ interface: event.target.value })}
            >
              {interfaces.map((name) => (
                <option key={name} value={name}>
                  {name}
                </option>
              ))}
            </Dropdown>
          </ControlField>

          {state.transport === "raw_redundant" ? (
            <ControlField label={backupInterfaceLabel} className="ke95-fill">
              <Dropdown
                className="ke95-fill"
                value={state.backup_interface}
                onChange={(event) => onPatch({ backup_interface: event.target.value })}
              >
                {interfaces.map((name) => (
                  <option key={name} value={name}>
                    {name}
                  </option>
                ))}
              </Dropdown>
            </ControlField>
          ) : null}
        </>
      )}
    </Columns>
  );
}

export function BusSetupSummary({ items }) {
  if (!items?.length) {
    return null;
  }

  return (
    <div className="ke95-grid ke95-grid--2">
      {items.map((item) => (
        <ControlField key={item.label} label={item.label}>
          <Mono as="div">{item.value}</Mono>
        </ControlField>
      ))}
    </div>
  );
}
