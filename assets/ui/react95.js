import "@react95/core/GlobalStyle";
import "@react95/core/themes/win95.css";
import "./react95.css";

import React, { useEffect, useRef, useState } from "react";
import { Button } from "@react95/core/Button";
import { Checkbox } from "@react95/core/Checkbox";
import { Fieldset } from "@react95/core/Fieldset";
import { Frame } from "@react95/core/Frame";
import { Input } from "@react95/core/Input";
import { Modal } from "@react95/core/Modal";
import { ProgressBar } from "@react95/core/ProgressBar";
import { Tab as React95Tab } from "@react95/core/Tab";
import { TextArea } from "@react95/core/TextArea";
import { Tabs as React95Tabs } from "@react95/core/Tabs";
import { TitleBar } from "@react95/core/TitleBar";

export { Button, Checkbox, Fieldset, Frame, Input, Modal, ProgressBar, React95Tab as Tab, TextArea, React95Tabs as Tabs, TitleBar };

function useWindowControls(windowRef) {
  const [fullscreenActive, setFullscreenActive] = useState(false);
  const [fullscreenSupported, setFullscreenSupported] = useState(false);
  const [minimized, setMinimized] = useState(false);
  const [layoutVersion, setLayoutVersion] = useState(0);
  const toggleMinimizedRef = useRef(null);

  useEffect(() => {
    const element = windowRef.current;
    if (!element) return undefined;

    const doc = element.ownerDocument;
    const onFullscreenChange = () => {
      setFullscreenActive(doc.fullscreenElement === element);
      setLayoutVersion((value) => value + 1);
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

  const toggleMinimized = async () => {
    if (minimized) {
      setMinimized(false);
      setLayoutVersion((value) => value + 1);
      return;
    }

    if (fullscreenActive) {
      const element = windowRef.current;
      const doc = element?.ownerDocument;

      try {
        await doc?.exitFullscreen?.();
      } catch (_error) {
        // Ignore browsers that reject fullscreen transitions in iframes.
      }
    }

    setMinimized(true);
    setLayoutVersion((value) => value + 1);
  };

  useEffect(() => {
    toggleMinimizedRef.current = toggleMinimized;
  }, [toggleMinimized]);

  useEffect(() => {
    const element = windowRef.current;
    if (!element) return undefined;

    const titleBar = element.querySelector(".ke95-window__titlebar, .draggable");
    if (!titleBar) return undefined;

    const onTitleBarClick = (event) => {
      if (!(event.target instanceof Element)) return;
      if (event.target.closest("button")) return;
      void toggleMinimizedRef.current?.();
    };

    titleBar.addEventListener("click", onTitleBarClick);

    return () => {
      titleBar.removeEventListener("click", onTitleBarClick);
    };
  }, [windowRef]);

  return {
    fullscreenActive,
    fullscreenSupported,
    layoutVersion,
    minimized,
    toggleFullscreen,
    toggleMinimized,
  };
}

export function Shell({ title, subtitle = null, status = null, toolbar = null, children, compact = false }) {
  const windowRef = useRef(null);
  const { fullscreenActive, fullscreenSupported, minimized, layoutVersion, toggleFullscreen, toggleMinimized } =
    useWindowControls(windowRef);
  const MinimizeToggle = minimized ? TitleBar.Restore : TitleBar.Minimize;
  const WindowToggle = fullscreenActive ? TitleBar.Restore : TitleBar.Maximize;
  const content =
    typeof children === "function"
      ? children({ fullscreenActive, fullscreenSupported, minimized, layoutVersion })
      : children;

  return (
    <Frame
      ref={windowRef}
      boxShadow="out"
      className={`ke95-shell${compact ? " ke95-shell--compact" : ""}${minimized ? " ke95-shell--minimized" : ""}`}
    >
      <TitleBar title={title} className="ke95-window__titlebar">
        <TitleBar.OptionsBox>
          <MinimizeToggle onClick={toggleMinimized} title={minimized ? "Restore window" : "Minimize window"} />
          <WindowToggle
            disabled={!fullscreenSupported || minimized}
            onClick={toggleFullscreen}
            title={fullscreenActive ? "Exit fullscreen" : "Enter fullscreen"}
          />
          <TitleBar.Close
            className="ke95-window__close"
            disabled
            title="Close unavailable inside Livebook"
          />
        </TitleBar.OptionsBox>
      </TitleBar>

      <div className="ke95-window__body">
        {subtitle || status || toolbar ? (
          <Fieldset className="ke95-window__meta">
            {subtitle ? <div className="ke95-window__subtitle">{subtitle}</div> : null}
            {status ? <div className="ke95-window__status">{status}</div> : null}
            {toolbar ? <div className="ke95-window__toolbar">{toolbar}</div> : null}
          </Fieldset>
        ) : null}

        <div className="ke95-window__content">{content}</div>
      </div>
    </Frame>
  );
}

export function ModalShell({ title, subtitle = null, status = null, toolbar = null, children, compact = false }) {
  const windowRef = useRef(null);
  const { fullscreenActive, fullscreenSupported, minimized, layoutVersion, toggleFullscreen, toggleMinimized } =
    useWindowControls(windowRef);
  const MinimizeToggle = minimized ? TitleBar.Restore : TitleBar.Minimize;
  const WindowToggle = fullscreenActive ? TitleBar.Restore : TitleBar.Maximize;
  const content =
    typeof children === "function"
      ? children({ fullscreenActive, fullscreenSupported, minimized, layoutVersion })
      : children;

  return (
    <Modal
      ref={windowRef}
      title={title}
      hasWindowButton={false}
      dragOptions={{ disabled: true }}
      style={{
        position: "relative",
        top: 0,
        left: 0,
        width: "100%",
        maxWidth: "100%",
        minWidth: 0,
        touchAction: "auto",
      }}
      className={`ke95-modal${compact ? " ke95-modal--compact" : ""}${minimized ? " ke95-modal--minimized" : ""}`}
      titleBarOptions={[
        <MinimizeToggle
          key="minimize"
          onClick={toggleMinimized}
          title={minimized ? "Restore window" : "Minimize window"}
        />,
        <WindowToggle
          key="fullscreen"
          disabled={!fullscreenSupported || minimized}
          onClick={toggleFullscreen}
          title={fullscreenActive ? "Exit fullscreen" : "Enter fullscreen"}
        />,
        <TitleBar.Close
          key="close"
          className="ke95-window__close"
          disabled
          title="Close unavailable inside Livebook"
        />,
      ]}
    >
      <Modal.Content className="ke95-modal__content">
        {subtitle || status || toolbar ? (
          <Fieldset className="ke95-window__meta">
            {subtitle ? <div className="ke95-window__subtitle">{subtitle}</div> : null}
            {status ? <div className="ke95-window__status">{status}</div> : null}
            {toolbar ? <div className="ke95-window__toolbar">{toolbar}</div> : null}
          </Fieldset>
        ) : null}

        <div className="ke95-window__content">{content}</div>
      </Modal.Content>
    </Modal>
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
