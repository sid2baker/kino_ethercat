import "./main.css";

import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

import { Frame, Mono, Shell, StatusBadge } from "../../ui/react95";

export async function init(ctx, data) {
  await ctx.importCSS("main.css");

  const root = createRoot(ctx.root);
  root.render(<LED ctx={ctx} data={data} />);
}

const COLOR_MAP = {
  green: "ke95-led__lamp--green",
  red: "ke95-led__lamp--red",
  yellow: "ke95-led__lamp--yellow",
  blue: "ke95-led__lamp--blue",
};

function LED({ ctx, data }) {
  const [value, setValue] = useState(data.value);
  const colorClass = COLOR_MAP[data.color] ?? COLOR_MAP.green;
  const isOn = isActive(value);

  useEffect(() => {
    ctx.handleEvent("value_updated", ({ value }) => setValue(value));
  }, [ctx]);

  return (
    <Shell
      title={data.label}
      subtitle="input indicator"
      compact
      status={<StatusBadge tone={isOn ? "ok" : "neutral"}>{isOn ? "on" : "off"}</StatusBadge>}
    >
      <Frame boxShadow="in" className="ke95-led">
        <span className={`ke95-led__lamp ${colorClass}${isOn ? " ke95-led__lamp--active" : ""}`} />
        <Mono>{isOn ? "active" : "inactive"}</Mono>
      </Frame>
    </Shell>
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
