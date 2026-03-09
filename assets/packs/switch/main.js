import "./main.css";

import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

export async function init(ctx, data) {
  await ctx.importCSS("main.css");

  const root = createRoot(ctx.root);
  root.render(<Switch ctx={ctx} data={data} />);
}

function Switch({ ctx, data }) {
  const [value, setValue] = useState(data.value);
  const isOn = value === 1;

  useEffect(() => {
    ctx.handleEvent("value_updated", ({ value }) => setValue(value));
  }, []);

  function handleToggle() {
    ctx.pushEvent("toggle");
  }

  return (
    <div className="ke-switch">
      <div className="ke-switch__copy">
        <div className="ke-switch__label">{data.label}</div>
        <div className="ke-switch__meta">manual output control</div>
      </div>

      <div className="ke-switch__controls">
        <span className={`ke-switch__badge ${isOn ? "ke-switch__badge--on" : "ke-switch__badge--off"}`}>
          {isOn ? "on" : "off"}
        </span>

        <button
          onClick={handleToggle}
          className={`ke-switch__toggle ${isOn ? "ke-switch__toggle--on" : "ke-switch__toggle--off"}`}
          role="switch"
          aria-checked={isOn}
        >
          <span className={`ke-switch__thumb ${isOn ? "ke-switch__thumb--on" : "ke-switch__thumb--off"}`} />
        </button>
      </div>
    </div>
  );
}
