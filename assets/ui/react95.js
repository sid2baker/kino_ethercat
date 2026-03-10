import "@react95/core/GlobalStyle";
import "@react95/core/themes/win95.css";
import "./react95.css";

import React from "react";
import { Button } from "@react95/core/Button";
import { Checkbox } from "@react95/core/Checkbox";
import { Fieldset } from "@react95/core/Fieldset";
import { Frame } from "@react95/core/Frame";
import { Input } from "@react95/core/Input";
import { ProgressBar } from "@react95/core/ProgressBar";
import { Tab } from "@react95/core/Tab";
import { Tabs } from "@react95/core/Tabs";
import { TextArea } from "@react95/core/TextArea";

export { Button, Checkbox, Fieldset, Frame, Input, ProgressBar, Tab, Tabs, TextArea };

export function Shell({ title, subtitle = null, status = null, toolbar = null, children, compact = false }) {
  return (
    <div className={`ke95-shell${compact ? " ke95-shell--compact" : ""}`}>
      <Frame boxShadow="out" className="ke95-header">
        <div className="ke95-header__copy">
          <div className="ke95-header__title">{title}</div>
          {subtitle ? <div className="ke95-header__subtitle">{subtitle}</div> : null}
        </div>
        {status || toolbar ? (
          <div className="ke95-header__meta">
            {status ? <div className="ke95-header__status">{status}</div> : null}
            {toolbar ? <div className="ke95-header__toolbar">{toolbar}</div> : null}
          </div>
        ) : null}
      </Frame>
      {children}
    </div>
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
