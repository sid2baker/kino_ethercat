import "@react95/core/GlobalStyle";
import "@react95/core/themes/win95.css";
import "./react95.css";

import React, { useEffect, useRef, useState } from "react";
import { Button } from "@react95/core/Button";
import { Checkbox } from "@react95/core/Checkbox";
import { Fieldset } from "@react95/core/Fieldset";
import { Frame } from "@react95/core/Frame";
import { Input } from "@react95/core/Input";
import { ProgressBar } from "@react95/core/ProgressBar";
import { Tab } from "@react95/core/Tab";
import { Tabs } from "@react95/core/Tabs";
import { TextArea } from "@react95/core/TextArea";
import { TitleBar } from "@react95/core/TitleBar";

export { Button, Checkbox, Fieldset, Frame, Input, ProgressBar, Tab, Tabs, TextArea, TitleBar };

export function Shell({ title, subtitle = null, status = null, toolbar = null, children, compact = false }) {
  const windowRef = useRef(null);
  const [fullscreenActive, setFullscreenActive] = useState(false);
  const [fullscreenSupported, setFullscreenSupported] = useState(false);

  useEffect(() => {
    const element = windowRef.current;
    if (!element) return undefined;

    const doc = element.ownerDocument;
    const onFullscreenChange = () => {
      setFullscreenActive(doc.fullscreenElement === element);
    };

    setFullscreenSupported(typeof element.requestFullscreen === "function");
    onFullscreenChange();

    doc.addEventListener("fullscreenchange", onFullscreenChange);

    return () => {
      doc.removeEventListener("fullscreenchange", onFullscreenChange);
    };
  }, []);

  const toggleFullscreen = async () => {
    const element = windowRef.current;
    if (!element || typeof element.requestFullscreen !== "function") return;

    const doc = element.ownerDocument;

    try {
      if (doc.fullscreenElement === element) {
        await doc.exitFullscreen?.();
      } else {
        await element.requestFullscreen();
      }
    } catch (_error) {
      // Livebook iframes may reject fullscreen depending on browser policy.
    }
  };

  const WindowToggle = fullscreenActive ? TitleBar.Restore : TitleBar.Maximize;

  return (
    <Frame ref={windowRef} boxShadow="out" className={`ke95-shell${compact ? " ke95-shell--compact" : ""}`}>
      <TitleBar title={title} className="ke95-window__titlebar">
        <TitleBar.OptionsBox>
          <WindowToggle
            disabled={!fullscreenSupported}
            onClick={toggleFullscreen}
            title={fullscreenActive ? "Exit fullscreen" : "Enter fullscreen"}
          />
          <TitleBar.Close disabled title="Close unavailable inside Livebook" />
        </TitleBar.OptionsBox>
      </TitleBar>

      <div className="ke95-window__body">
        {subtitle || status || toolbar ? (
          <Frame boxShadow="in" className="ke95-window__meta">
            {subtitle ? <div className="ke95-window__subtitle">{subtitle}</div> : null}
            {status ? <div className="ke95-window__status">{status}</div> : null}
            {toolbar ? <div className="ke95-window__toolbar">{toolbar}</div> : null}
          </Frame>
        ) : null}

        <div className="ke95-window__content">{children}</div>
      </div>
    </Frame>
  );
}

export function Panel({ title, actions = null, children, className = "" }) {
  return (
    <Fieldset legend={title} className={`ke95-panel ${className}`.trim()}>
      {actions ? <div className="ke95-panel__actions">{actions}</div> : null}
      {children}
    </Fieldset>
  );
}

export function ControlField({ label = null, help = null, children, className = "" }) {
  return (
    <label className={`ke95-field ${className}`.trim()}>
      {label ? <div className="ke95-field__label">{label}</div> : null}
      {children}
      {help ? <div className="ke95-field__help">{help}</div> : null}
    </label>
  );
}

export function SummaryGrid({ items }) {
  if (!items?.length) return null;

  return (
    <div className="ke95-summary">
      {items.map((item) => (
        <Frame key={item.label} boxShadow="in" className="ke95-summary__item">
          <div className="ke95-summary__label">{item.label}</div>
          <div className="ke95-summary__value">{item.value}</div>
        </Frame>
      ))}
    </div>
  );
}

export function StatusBadge({ tone = "neutral", children }) {
  return <span className={`ke95-badge ke95-badge--${tone}`}>{children}</span>;
}

export function MessageLine({ tone = "info", children }) {
  if (!children) return null;
  return <Frame className={`ke95-message ke95-message--${tone}`}>{children}</Frame>;
}

export function EmptyState({ children, action = null }) {
  return (
    <Frame boxShadow="in" className="ke95-empty">
      <div>{children}</div>
      {action}
    </Frame>
  );
}

export function InlineButtons({ children, className = "" }) {
  return <div className={`ke95-inline-buttons ${className}`.trim()}>{children}</div>;
}

export function DataTable({ headers, children, className = "" }) {
  return (
    <div className="ke95-table-wrap">
      <table className={`ke95-table ${className}`.trim()}>
        <thead>
          <tr>
            {headers.map((header) => (
              <th key={header}>{header}</th>
            ))}
          </tr>
        </thead>
        <tbody>{children}</tbody>
      </table>
    </div>
  );
}

export function Mono({ as: Component = "span", children, className = "" }) {
  return <Component className={`ke95-mono ${className}`.trim()}>{children}</Component>;
}

export function Dropdown({ options = null, children = null, className = "", ...props }) {
  return (
    <Frame boxShadow="in" className={`ke95-select ${className}`.trim()}>
      <select {...props} className="ke95-select__control">
        {children ??
          (options ?? []).map((option) => (
            <option key={option} value={option}>
              {option}
            </option>
          ))}
      </select>
    </Frame>
  );
}
