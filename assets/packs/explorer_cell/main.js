import "./main.css";

import React, { startTransition, useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";

import {
  Button,
  ControlField,
  DataTable,
  Dropdown,
  EmptyState,
  Input,
  MessageLine,
  Panel,
  PropertyList,
  Shell,
  Stack,
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

  const toolbar = (state.actions ?? []).map((action) => (
    <Button key={action.id} onClick={() => ctx.pushEvent(action.id, {})}>
      {action.label}
    </Button>
  ));

  return (
    <Shell title={state.title} subtitle={state.description} toolbar={toolbar.length > 0 ? toolbar : null}>
      <Stack>
        <FieldsArea fields={state.fields ?? []} values={values} onChange={updateField} />
        <SectionsArea sections={state.sections ?? []} />
      </Stack>
    </Shell>
  );
}

function FieldsArea({ fields, values, onChange }) {
  const groupedFields = groupFields(fields);

  if (groupedFields.length === 0) {
    return null;
  }

  if (groupedFields.length === 1 && groupedFields[0].title === "Parameters") {
    return (
      <Panel title="Parameters">
        <FieldGrid fields={groupedFields[0].fields} values={values} onChange={onChange} />
      </Panel>
    );
  }

  return groupedFields.map((group) => (
    <Panel key={group.title} title={group.title}>
      <FieldGrid fields={group.fields} values={values} onChange={onChange} />
    </Panel>
  ));
}

function FieldGrid({ fields, values, onChange }) {
  const gridClass = usesSingleColumn(fields) ? "ke95-grid ke95-grid--1" : "ke95-grid ke95-grid--2";

  return (
    <div className={gridClass}>
      {fields.map((field) => (
        <Field
          key={field.name}
          field={field}
          value={values[field.name] ?? ""}
          onChange={(value) => onChange(field.name, value)}
        />
      ))}
    </div>
  );
}

function SectionsArea({ sections }) {
  if (!sections?.length) {
    return null;
  }

  return sections.map((section, index) => <SectionBlock key={`${section.title ?? section.type}-${index}`} section={section} />);
}

function SectionBlock({ section }) {
  if (section.type === "message") {
    return (
      <Panel title={section.title ?? "Status"}>
        <MessageLine tone={section.tone ?? "info"}>{section.text}</MessageLine>
      </Panel>
    );
  }

  if (section.type === "properties") {
    return (
      <Panel title={section.title}>
        {section.items?.length ? (
          <PropertyList items={section.items} />
        ) : (
          <EmptyState>No details available.</EmptyState>
        )}
      </Panel>
    );
  }

  if (section.type === "list") {
    return (
      <Panel title={section.title}>
        {section.items?.length ? (
          <ul className="ke95-explorer__list">
            {section.items.map((item, index) => (
              <li key={`${item}-${index}`}>{item}</li>
            ))}
          </ul>
        ) : (
          <EmptyState>Nothing to show.</EmptyState>
        )}
      </Panel>
    );
  }

  if (section.type === "table") {
    return (
      <Panel title={section.title}>
        {section.rows?.length ? (
          <DataTable headers={section.headers ?? []}>
            {section.rows.map((row, rowIndex) => (
              <tr key={rowIndex}>
                {row.map((cell, cellIndex) => (
                  <td key={cellIndex}>{cell}</td>
                ))}
              </tr>
            ))}
          </DataTable>
        ) : (
          <EmptyState>No rows available.</EmptyState>
        )}
      </Panel>
    );
  }

  return null;
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

function groupFields(fields) {
  if (!fields?.length) {
    return [];
  }

  if (fields.every((field) => !field.section)) {
    return [{ title: "Parameters", fields }];
  }

  const groups = [];
  const lookup = new Map();

  fields.forEach((field) => {
    const title = field.section ?? "Parameters";
    const existing = lookup.get(title);

    if (existing) {
      existing.fields.push(field);
      return;
    }

    const group = { title, fields: [field] };
    groups.push(group);
    lookup.set(title, group);
  });

  return groups;
}

function usesSingleColumn(fields) {
  return fields.some((field) => field.type === "textarea") || fields.length === 1;
}
