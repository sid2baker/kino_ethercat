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

  useEffect(() => {
    ctx.handleEvent("value_updated", ({ value }) => setValue(value));
  }, []);

  return (
    <div className="p-2 min-w-32">
      <div className="text-xs text-gray-400 font-mono mb-0.5">{data.label}</div>
      <div className="text-sm text-gray-700 font-mono break-all">
        {value ?? <span className="text-gray-300">—</span>}
      </div>
    </div>
  );
}
