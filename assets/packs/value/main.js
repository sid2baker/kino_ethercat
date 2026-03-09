import "./main.css";

import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

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
  }, []);

  return (
    <div className="p-2 min-w-32">
      <div className="text-xs text-gray-400 font-mono mb-0.5">{data.label}</div>
      <div className="text-sm text-gray-700 font-mono break-all">
        {value ?? <span className="text-gray-300">—</span>}
      </div>
      <div className="mt-1 text-[11px] text-gray-400 font-mono">
        {updatedAtUs == null ? "awaiting sample time" : `updated ${updatedAtUs} us`}
      </div>
    </div>
  );
}
