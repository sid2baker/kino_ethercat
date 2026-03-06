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
    <div className="flex items-center gap-3 p-2">
      <button
        onClick={handleToggle}
        className={`relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 focus:outline-none ${
          isOn ? "bg-green-500" : "bg-gray-300"
        }`}
        role="switch"
        aria-checked={isOn}
      >
        <span
          className={`pointer-events-none inline-block h-5 w-5 rounded-full bg-white shadow-md transform transition-transform duration-200 ${
            isOn ? "translate-x-5" : "translate-x-0"
          }`}
        />
      </button>
      <span className="text-sm text-gray-700 font-mono">{data.label}</span>
    </div>
  );
}
