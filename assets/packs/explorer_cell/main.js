import "./main.css";

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function renderOptions(options, currentValue) {
  return options
    .map((option) => {
      const value = escapeHtml(option.value);
      const label = escapeHtml(option.label);
      const selected = option.value === currentValue ? " selected" : "";
      return `<option value="${value}"${selected}>${label}</option>`;
    })
    .join("");
}

function renderDatalistOptions(options) {
  return options
    .map((option) => `<option value="${escapeHtml(option.value)}">${escapeHtml(option.label)}</option>`)
    .join("");
}

function renderField(field, value) {
  const id = `field-${field.name}`;
  const help = field.help ? `<div class="kino-ethercat-explorer__help">${escapeHtml(field.help)}</div>` : "";

  if (field.type === "select") {
    return `
      <label class="kino-ethercat-explorer__field" for="${id}">
        <span class="kino-ethercat-explorer__label">${escapeHtml(field.label)}</span>
        <select id="${id}" name="${escapeHtml(field.name)}" class="kino-ethercat-explorer__input">
          ${renderOptions(field.options ?? [], value)}
        </select>
        ${help}
      </label>
    `;
  }

  if (field.type === "textarea") {
    return `
      <label class="kino-ethercat-explorer__field" for="${id}">
        <span class="kino-ethercat-explorer__label">${escapeHtml(field.label)}</span>
        <textarea
          id="${id}"
          name="${escapeHtml(field.name)}"
          class="kino-ethercat-explorer__input kino-ethercat-explorer__textarea"
          placeholder="${escapeHtml(field.placeholder ?? "")}"
        >${escapeHtml(value)}</textarea>
        ${help}
      </label>
    `;
  }

  if (field.type === "datalist") {
    const listId = `${id}-list`;

    return `
      <label class="kino-ethercat-explorer__field" for="${id}">
        <span class="kino-ethercat-explorer__label">${escapeHtml(field.label)}</span>
        <input
          id="${id}"
          name="${escapeHtml(field.name)}"
          list="${listId}"
          class="kino-ethercat-explorer__input"
          value="${escapeHtml(value)}"
          placeholder="${escapeHtml(field.placeholder ?? "")}"
        />
        <datalist id="${listId}">
          ${renderDatalistOptions(field.options ?? [])}
        </datalist>
        ${help}
      </label>
    `;
  }

  return `
    <label class="kino-ethercat-explorer__field" for="${id}">
      <span class="kino-ethercat-explorer__label">${escapeHtml(field.label)}</span>
      <input
        id="${id}"
        name="${escapeHtml(field.name)}"
        class="kino-ethercat-explorer__input"
        value="${escapeHtml(value)}"
        placeholder="${escapeHtml(field.placeholder ?? "")}"
      />
      ${help}
    </label>
  `;
}

export async function init(ctx, payload) {
  await ctx.importCSS("main.css");

  let state = payload;

  const collectValues = () => {
    const values = {};

    for (const field of state.fields) {
      const input = ctx.root.querySelector(`[name="${field.name}"]`);
      values[field.name] = input ? input.value : state.values[field.name] ?? "";
    }

    return values;
  };

  const sync = () => ctx.pushEvent("update", collectValues());

  const bind = () => {
    ctx.root.querySelectorAll("[name]").forEach((element) => {
      element.addEventListener("change", () => {
        sync();
      });
    });

    ctx.root.querySelectorAll("[data-action-id]").forEach((element) => {
      element.addEventListener("click", () => {
        ctx.pushEvent(element.dataset.actionId, {});
      });
    });
  };

  const render = (nextPayload = state) => {
    state = nextPayload;

    const fields = state.fields
      .map((field) => renderField(field, state.values[field.name] ?? ""))
      .join("");

    const actions = (state.actions ?? [])
      .map(
        (action) =>
          `<button type="button" class="kino-ethercat-explorer__action" data-action-id="${escapeHtml(action.id)}">${escapeHtml(action.label)}</button>`,
      )
      .join("");

    const description = state.description
      ? `<div class="kino-ethercat-explorer__description">${escapeHtml(state.description)}</div>`
      : "";

    ctx.root.innerHTML = `
      <div class="kino-ethercat-explorer">
        <div class="kino-ethercat-explorer__header">
          <div class="kino-ethercat-explorer__header-main">
            <h3 class="kino-ethercat-explorer__title">${escapeHtml(state.title)}</h3>
            ${description}
          </div>
          <div class="kino-ethercat-explorer__actions">${actions}</div>
        </div>
        <div class="kino-ethercat-explorer__grid">${fields}</div>
      </div>
    `;

    bind();
  };

  ctx.handleEvent("snapshot", render);
  ctx.handleSync(() => {
    const active = document.activeElement;

    if (active && ctx.root.contains(active)) {
      active.dispatchEvent(new Event("change", { bubbles: true }));
    } else {
      sync();
    }
  });

  render(payload);
}
