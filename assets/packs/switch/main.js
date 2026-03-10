import "./main.css";

import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

import { Button, Frame, InlineButtons, Mono, Shell, StatusBadge } from "../../ui/react95";

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
  }, [ctx]);

  return (
    <Shell
      title={data.label}
      subtitle="manual output control"
      compact
      status={<StatusBadge tone={isOn ? "ok" : "neutral"}>{isOn ? "on" : "off"}</StatusBadge>}
    >
      <Frame boxShadow="in" className="ke95-switch">
        <Mono>{isOn ? "energized" : "de-energized"}</Mono>
        <InlineButtons>
          <Button onClick={() => ctx.pushEvent("toggle")}>{isOn ? "Turn off" : "Turn on"}</Button>
        </InlineButtons>
      </Frame>
    </Shell>
  );
}
