import "./main.css";

import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

export async function init(ctx, data) {
  await ctx.importCSS("main.css");

  const root = createRoot(ctx.root);
  root.render(<LED ctx={ctx} data={data} />);
}

const COLOR_MAP = {
  green: { on: "ke-indicator__dot--green-on", off: "ke-indicator__dot--green-off" },
  red: { on: "ke-indicator__dot--red-on", off: "ke-indicator__dot--red-off" },
  yellow: { on: "ke-indicator__dot--yellow-on", off: "ke-indicator__dot--yellow-off" },
  blue: { on: "ke-indicator__dot--blue-on", off: "ke-indicator__dot--blue-off" },
};

function LED({ ctx, data }) {
  const [value, setValue] = useState(data.value);
  const colors = COLOR_MAP[data.color] ?? COLOR_MAP.green;
  const isOn = isActive(value);

  useEffect(() => {
    ctx.handleEvent("value_updated", ({ value }) => setValue(value));
  }, []);

  return (
    <div className="ke-indicator">
      <div className="ke-indicator__main">
        <span className={`ke-indicator__dot ${isOn ? colors.on : colors.off}`} />
        <div className="ke-indicator__copy">
          <div className="ke-indicator__label">{data.label}</div>
          <div className="ke-indicator__meta">{isOn ? "active" : "inactive"}</div>
        </div>
      </div>
      <span className={`ke-indicator__badge ${isOn ? "ke-indicator__badge--on" : "ke-indicator__badge--off"}`}>
        {isOn ? "on" : "off"}
      </span>
    </div>
  );
}

function isActive(value) {
  if (typeof value === "boolean") {
    return value;
  }

  if (typeof value === "number") {
    return value !== 0;
  }

  if (typeof value === "string") {
    return value !== "0" && value.toLowerCase() !== "false" && value !== "";
  }

  return false;
}
