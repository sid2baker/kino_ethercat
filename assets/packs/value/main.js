import "./main.css";

import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

import { Frame, Mono, Shell } from "../../ui/react95";

export async function init(ctx, data) {
  await ctx.importCSS("main.css");
  const root = createRoot(ctx.root);
  root.render(<Value ctx={ctx} data={data} />);
}

function Value({ ctx, data }) {
  const [value, setValue] = useState(data.value);
  const [updatedAtUs, setUpdatedAtUs] = useState(data.updated_at_us);

  useEffect(() => {
    ctx.handleEvent("value_updated", ({ value, updated_at_us }) => {
      setValue(value);
      setUpdatedAtUs(updated_at_us);
    });
  }, [ctx]);

  return (
    <Shell title={data.label} subtitle="input sample" compact>
      <Frame boxShadow="in" className="ke95-value">
        <Mono as="div" className="ke95-value__current">
          {value ?? "—"}
        </Mono>
        <Mono as="div" className="ke95-value__meta">
          {updatedAtUs == null ? "awaiting sample time" : `updated ${updatedAtUs} us`}
        </Mono>
      </Frame>
    </Shell>
  );
}
