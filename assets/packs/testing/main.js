import "./main.css";

import React, { useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";

const STATUS_STYLES = {
  idle: "bg-stone-200 text-stone-700",
  running: "bg-sky-100 text-sky-800",
  passed: "bg-emerald-100 text-emerald-800",
  failed: "bg-rose-100 text-rose-800",
  cancelled: "bg-amber-100 text-amber-800",
};

const STEP_STYLES = {
  pending: "border-stone-200 bg-white/75 text-stone-500",
  running: "border-sky-200 bg-sky-50 text-sky-800",
  passed: "border-emerald-200 bg-emerald-50 text-emerald-800",
  failed: "border-rose-200 bg-rose-50 text-rose-800",
};

const BUTTON_STYLES = {
  primary: "border-stone-900 bg-stone-900 text-white hover:bg-stone-700",
  secondary: "border-stone-300 bg-white text-stone-700 hover:border-stone-400 hover:bg-stone-100",
};

export async function init(ctx, data) {
  await ctx.importCSS("main.css");
  const root = createRoot(ctx.root);
  root.render(<TestingPanel ctx={ctx} data={data} />);
}

function badgeClass(value, styles) {
  return styles[value] ?? styles.idle ?? "bg-stone-200 text-stone-700";
}

function formatDuration(durationMs) {
  if (durationMs == null) return "not started";
  if (durationMs < 1000) return `${durationMs} ms`;
  return `${(durationMs / 1000).toFixed(2)} s`;
}

function formatTime(atMs) {
  if (atMs == null) return "n/a";
  return new Date(atMs).toLocaleTimeString([], {
    hour12: false,
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
}

function normalizeOptions(options) {
  return {
    attach_telemetry: Boolean(options.attach_telemetry),
    telemetry_groups: Array.isArray(options.telemetry_groups) ? options.telemetry_groups : [],
  };
}

function Badge({ label, tone }) {
  return (
    <span className={`inline-flex items-center rounded-full px-2 py-0.5 font-mono text-[11px] font-medium ${tone}`}>
      {label}
    </span>
  );
}

function SummaryCard({ label, value, tone = "text-stone-700" }) {
  return (
    <div className="rounded-2xl border border-stone-200 bg-white/80 px-3 py-3">
      <div className="text-[11px] uppercase tracking-[0.18em] text-stone-400">{label}</div>
      <div className={`mt-1 font-mono text-xs ${tone}`}>{value}</div>
    </div>
  );
}

function OptionToggle({ checked, disabled, label, description, onChange }) {
  return (
    <label className={`ke-testing__toggle ${disabled ? "ke-testing__toggle--disabled" : ""}`}>
      <input type="checkbox" checked={checked} disabled={disabled} onChange={onChange} />
      <span className="ke-testing__toggle-copy">
        <span className="ke-testing__toggle-label">{label}</span>
        <span className="ke-testing__toggle-description">{description}</span>
      </span>
    </label>
  );
}

function Controls({ ctx, snapshot, options, setOptions }) {
  const running = snapshot.running;
  const availableGroups = snapshot.options.available_groups ?? [];

  const pushOptions = (nextOptions) => {
    setOptions(nextOptions);

    ctx.pushEvent("update_options", {
      attach_telemetry: nextOptions.attach_telemetry,
      telemetry_groups: nextOptions.telemetry_groups,
    });
  };

  const setAttachTelemetry = (checked) => {
    pushOptions({
      ...options,
      attach_telemetry: checked,
      telemetry_groups: checked ? options.telemetry_groups : [],
    });
  };

  const toggleGroup = (groupId, checked) => {
    const nextGroups = checked
      ? [...new Set([...options.telemetry_groups, groupId])]
      : options.telemetry_groups.filter((value) => value !== groupId);

    pushOptions({
      ...options,
      attach_telemetry: checked ? true : options.attach_telemetry,
      telemetry_groups: nextGroups,
    });
  };

  return (
    <section className="ke-testing__controls">
      <div className="ke-testing__controls-copy">
        <div className="ke-testing__eyebrow">Run Options</div>
        <h3 className="ke-testing__section-title">Capture extra evidence when you need it</h3>
        <p className="ke-testing__section-text">
          Start the scenario from here and choose whether the run should subscribe to EtherCAT telemetry while it executes.
        </p>
      </div>

      <div className="ke-testing__controls-grid">
        <OptionToggle
          checked={options.attach_telemetry}
          disabled={running}
          label="Attach telemetry events"
          description="Subscribe to runtime telemetry while the scenario is running and keep a short event trail in the report."
          onChange={(event) => setAttachTelemetry(event.target.checked)}
        />

        <div className="ke-testing__group-picker">
          <div className="ke-testing__group-title">Telemetry groups</div>
          <div className="ke-testing__group-list">
            {availableGroups.map((group) => (
              <OptionToggle
                key={group.id}
                checked={options.telemetry_groups.includes(group.id)}
                disabled={running || !options.attach_telemetry}
                label={group.label}
                description={`Collect ${group.label.toLowerCase()} events during this run.`}
                onChange={(event) => toggleGroup(group.id, event.target.checked)}
              />
            ))}
          </div>
        </div>

        <div className="ke-testing__actions">
          <button
            type="button"
            disabled={running}
            className={`ke-testing__button ${BUTTON_STYLES.primary} ${running ? "ke-testing__button--disabled" : ""}`}
            onClick={() => ctx.pushEvent("run", {})}
          >
            {running ? "Running…" : "Run Scenario"}
          </button>

          <button
            type="button"
            disabled={running}
            className={`ke-testing__button ${BUTTON_STYLES.secondary} ${running ? "ke-testing__button--disabled" : ""}`}
            onClick={() => ctx.pushEvent("reset", {})}
          >
            Reset View
          </button>
        </div>
      </div>
    </section>
  );
}

function StepCard({ step }) {
  return (
    <article className={`ke-testing__step ${badgeClass(step.status, STEP_STYLES)}`}>
      <div className="ke-testing__step-header">
        <div>
          <div className="ke-testing__eyebrow">Step {step.index + 1}</div>
          <h4 className="ke-testing__step-title">{step.title}</h4>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Badge label={step.kind} tone="bg-white/80 text-stone-600" />
          <Badge label={step.status} tone={badgeClass(step.status, STATUS_STYLES)} />
        </div>
      </div>

      <div className="ke-testing__step-meta">
        <span>{step.duration_ms == null ? "pending" : formatDuration(step.duration_ms)}</span>
        {step.detail ? <span>{step.detail}</span> : null}
      </div>

      {step.observations.length > 0 ? (
        <div className="ke-testing__observation-list">
          {step.observations.map((observation) => (
            <div key={`${step.index}-${observation.at_ms}-${observation.value}`} className="ke-testing__observation">
              <span>{formatTime(observation.at_ms)}</span>
              <span>{observation.value}</span>
            </div>
          ))}
        </div>
      ) : (
        <div className="ke-testing__step-empty">No observations captured yet.</div>
      )}
    </article>
  );
}

function TelemetryPanel({ snapshot }) {
  const enabledGroups = snapshot.options.telemetry_groups ?? [];

  return (
    <section className="ke-testing__telemetry">
      <div className="ke-testing__telemetry-header">
        <div>
          <div className="ke-testing__eyebrow">Telemetry Trail</div>
          <h3 className="ke-testing__section-title">Runtime events captured during the run</h3>
        </div>
        <Badge
          label={snapshot.options.attach_telemetry ? `${snapshot.telemetry_events.length} events` : "disabled"}
          tone={snapshot.options.attach_telemetry ? "bg-sky-100 text-sky-800" : "bg-stone-200 text-stone-600"}
        />
      </div>

      {snapshot.options.attach_telemetry ? (
        <>
          <div className="ke-testing__telemetry-groups">
            {enabledGroups.length > 0 ? enabledGroups.map((group) => (
              <Badge key={group} label={group} tone="bg-white/80 text-stone-600" />
            )) : <span className="ke-testing__muted">No groups selected.</span>}
          </div>

          {snapshot.telemetry_events.length > 0 ? (
            <div className="ke-testing__event-list">
              {snapshot.telemetry_events.map((event) => (
                <article key={event.id} className="ke-testing__event">
                  <div className="ke-testing__event-row">
                    <span className="ke-testing__event-time">{formatTime(event.at_ms)}</span>
                    <Badge label={event.group} tone="bg-sky-100 text-sky-800" />
                    <span className="ke-testing__event-name">{event.event}</span>
                  </div>
                  <div className="ke-testing__event-detail">{event.detail}</div>
                </article>
              ))}
            </div>
          ) : (
            <div className="ke-testing__empty">
              Waiting for events. If the run is short, you may need to enable a broader group such as bus or domain.
            </div>
          )}
        </>
      ) : (
        <div className="ke-testing__empty">
          Telemetry capture is disabled for this run. Enable it before starting if you want the report to include runtime events.
        </div>
      )}
    </section>
  );
}

function TestingPanel({ ctx, data }) {
  const [snapshot, setSnapshot] = useState(data);
  const [options, setOptions] = useState(() => normalizeOptions(data.options ?? {}));

  useEffect(() => {
    ctx.handleEvent("snapshot", (nextSnapshot) => {
      setSnapshot(nextSnapshot);
    });
  }, [ctx]);

  useEffect(() => {
    setOptions(normalizeOptions(snapshot.options ?? {}));
  }, [snapshot.options]);

  const summaryCards = useMemo(
    () => [
      { label: "Status", value: snapshot.status, tone: "text-stone-800" },
      { label: "Duration", value: formatDuration(snapshot.duration_ms) },
      { label: "Started", value: formatTime(snapshot.started_at_ms) },
      { label: "Timeout", value: formatDuration(snapshot.timeout_ms) },
    ],
    [snapshot.duration_ms, snapshot.started_at_ms, snapshot.status, snapshot.timeout_ms],
  );

  return (
    <div className="kino-ethercat-testing space-y-4 p-4 font-sans text-sm text-stone-700">
      <header className="ke-testing__hero">
        <div className="ke-testing__hero-copy">
          <div className="ke-testing__eyebrow">Scenario Run</div>
          <div className="flex flex-wrap items-center gap-2">
            <h2 className="ke-testing__hero-title">{snapshot.title}</h2>
            <Badge label={snapshot.status} tone={badgeClass(snapshot.status, STATUS_STYLES)} />
          </div>
          {snapshot.description ? <p className="ke-testing__hero-text">{snapshot.description}</p> : null}
        </div>

        {snapshot.tags.length > 0 ? (
          <div className="flex flex-wrap gap-2">
            {snapshot.tags.map((tag) => (
              <Badge key={tag} label={tag} tone="bg-white/80 text-stone-600" />
            ))}
          </div>
        ) : null}
      </header>

      <section className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        {summaryCards.map((card) => (
          <SummaryCard key={card.label} label={card.label} value={card.value} tone={card.tone} />
        ))}
      </section>

      {snapshot.failure ? (
        <section className="rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3">
          <div className="ke-testing__eyebrow">Failure</div>
          <div className="mt-1 font-mono text-xs text-rose-800">{snapshot.failure}</div>
        </section>
      ) : null}

      <Controls ctx={ctx} snapshot={snapshot} options={options} setOptions={setOptions} />

      <section className="ke-testing__steps">
        <div className="ke-testing__steps-header">
          <div>
            <div className="ke-testing__eyebrow">Execution Trace</div>
            <h3 className="ke-testing__section-title">Step-by-step progress</h3>
          </div>
          <Badge
            label={`${snapshot.steps.filter((step) => step.status === "passed").length}/${snapshot.steps.length} passed`}
            tone="bg-white/80 text-stone-600"
          />
        </div>

        <div className="ke-testing__step-grid">
          {snapshot.steps.map((step) => (
            <StepCard key={step.index} step={step} />
          ))}
        </div>
      </section>

      <TelemetryPanel snapshot={snapshot} />
    </div>
  );
}
