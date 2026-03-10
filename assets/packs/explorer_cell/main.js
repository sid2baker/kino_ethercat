import "./main.css";

import React, { startTransition, useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";

import {
  Button,
  ControlField,
  Dropdown,
  Input,
  Panel,
  Shell,
  TextArea,
} from "../../ui/react95";

export async function init(ctx, payload) {
  await ctx.importCSS("main.css");

  const root = createRoot(ctx.root);
  root.render(<ExplorerCell ctx={ctx} payload={payload} />);
}

function ExplorerCell({ ctx, payload }) {
  const [state, setState] = useState(payload);
  const [values, setValues] = useState(payload.values ?? {});
  const valuesRef = useRef(values);

  useEffect(() => {
    valuesRef.current = values;
  }, [values]);

  useEffect(() => {
    ctx.handleEvent("snapshot", (nextPayload) => {
      startTransition(() => {
        setState(nextPayload);
        setValues(nextPayload.values ?? {});
      });
    });

    ctx.handleSync(() => {
      const active = document.activeElement;

      if (active && ctx.root.contains(active) && typeof active.blur === "function") {
        active.blur();
      } else {
        ctx.pushEvent("update", valuesRef.current);
      }
    });
  }, [ctx]);

  const updateField = (name, value) => {
    const nextValues = { ...values, [name]: value };
    setValues(nextValues);
    ctx.pushEvent("update", nextValues);
  };

  return (
    <Shell title={state.title} subtitle={state.description}>
      <Panel
        title="Parameters"
        actions={(state.actions ?? []).map((action) => (
          <Button key={action.id} onClick={() => ctx.pushEvent(action.id, {})}>
            {action.label}
          </Button>
        ))}
      >
        <div className="ke95-grid ke95-grid--2">
          {state.fields.map((field) => (
            <Field
              key={field.name}
              field={field}
              value={values[field.name] ?? ""}
              onChange={(value) => updateField(field.name, value)}
            />
          ))}
        </div>
      </Panel>
    </Shell>
  );
}

function Field({ field, value, onChange }) {
  if (field.type === "select") {
    return (
      <ControlField label={field.label} help={field.help}>
        <Dropdown value={value} className="ke95-fill" onChange={(event) => onChange(event.target.value)}>
          {(field.options ?? []).map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </Dropdown>
      </ControlField>
    );
  }

  if (field.type === "textarea") {
    return (
      <ControlField label={field.label} help={field.help}>
        <TextArea
          className="ke95-fill ke95-explorer__textarea"
          placeholder={field.placeholder ?? ""}
          value={value}
          onChange={(event) => onChange(event.target.value)}
        />
      </ControlField>
    );
  }

  if (field.type === "datalist") {
    const listId = `ke95-explorer-${field.name}-list`;

    return (
      <ControlField label={field.label} help={field.help}>
        <>
          <Input
            className="ke95-fill"
            list={listId}
            placeholder={field.placeholder ?? ""}
            value={value}
            onChange={(event) => onChange(event.target.value)}
          />
          <datalist id={listId}>
            {(field.options ?? []).map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </datalist>
        </>
      </ControlField>
    );
  }

  return (
    <ControlField label={field.label} help={field.help}>
      <Input
        className="ke95-fill"
        placeholder={field.placeholder ?? ""}
        value={value}
        onChange={(event) => onChange(event.target.value)}
      />
    </ControlField>
  );
}
