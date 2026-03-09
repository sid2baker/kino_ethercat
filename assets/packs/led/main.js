import "./main.css";

import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

export async function init(ctx, data) {
  await ctx.importCSS("main.css");

  const root = createRoot(ctx.root);
  root.render(<LED ctx={ctx} data={data} />);
}

const COLOR_MAP = {
  green: { on: "bg-green-400 shadow-green-400", off: "bg-green-900" },
  red: { on: "bg-red-400 shadow-red-400", off: "bg-red-900" },
  yellow: { on: "bg-yellow-300 shadow-yellow-300", off: "bg-yellow-900" },
  blue: { on: "bg-blue-400 shadow-blue-400", off: "bg-blue-900" },
};

function LED({ ctx, data }) {
  const [value, setValue] = useState(data.value);
  const colors = COLOR_MAP[data.color] ?? COLOR_MAP.green;
  const isOn = isActive(value);

  useEffect(() => {
    ctx.handleEvent("value_updated", ({ value }) => setValue(value));
  }, []);

  return (
    <div className="flex items-center gap-2 p-2">
      <div
        className={`w-4 h-4 rounded-full transition-all duration-150 ${
          isOn ? `${colors.on} shadow-[0_0_8px_2px]` : colors.off
        }`}
      />
      <span className="text-sm text-gray-700 font-mono">{data.label}</span>
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
