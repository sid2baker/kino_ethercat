function t(e){return String(e!=null?e:"").replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;").replaceAll('"',"&quot;").replaceAll("'","&#39;")}function _(e,o){return e.map(r=>{let n=t(r.value),i=t(r.label),c=r.value===o?" selected":"";return`<option value="${n}"${c}>${i}</option>`}).join("")}function u(e){return e.map(o=>`<option value="${t(o.value)}">${t(o.label)}</option>`).join("")}function x(e,o){var i,c,p,a,s;let r=`field-${e.name}`,n=e.help?`<div class="kino-ethercat-explorer__help">${t(e.help)}</div>`:"";if(e.type==="select")return`
      <label class="kino-ethercat-explorer__field" for="${r}">
        <span class="kino-ethercat-explorer__label">${t(e.label)}</span>
        <select id="${r}" name="${t(e.name)}" class="kino-ethercat-explorer__input">
          ${_((i=e.options)!=null?i:[],o)}
        </select>
        ${n}
      </label>
    `;if(e.type==="textarea")return`
      <label class="kino-ethercat-explorer__field" for="${r}">
        <span class="kino-ethercat-explorer__label">${t(e.label)}</span>
        <textarea
          id="${r}"
          name="${t(e.name)}"
          class="kino-ethercat-explorer__input kino-ethercat-explorer__textarea"
          placeholder="${t((c=e.placeholder)!=null?c:"")}"
        >${t(o)}</textarea>
        ${n}
      </label>
    `;if(e.type==="datalist"){let l=`${r}-list`;return`
      <label class="kino-ethercat-explorer__field" for="${r}">
        <span class="kino-ethercat-explorer__label">${t(e.label)}</span>
        <input
          id="${r}"
          name="${t(e.name)}"
          list="${l}"
          class="kino-ethercat-explorer__input"
          value="${t(o)}"
          placeholder="${t((p=e.placeholder)!=null?p:"")}"
        />
        <datalist id="${l}">
          ${u((a=e.options)!=null?a:[])}
        </datalist>
        ${n}
      </label>
    `}return`
    <label class="kino-ethercat-explorer__field" for="${r}">
      <span class="kino-ethercat-explorer__label">${t(e.label)}</span>
      <input
        id="${r}"
        name="${t(e.name)}"
        class="kino-ethercat-explorer__input"
        value="${t(o)}"
        placeholder="${t((s=e.placeholder)!=null?s:"")}"
      />
      ${n}
    </label>
  `}async function $(e,o){await e.importCSS("main.css");let r=o,n=()=>{var s;let a={};for(let l of r.fields){let h=e.root.querySelector(`[name="${l.name}"]`);a[l.name]=h?h.value:(s=r.values[l.name])!=null?s:""}return a},i=()=>e.pushEvent("update",n()),c=()=>{e.root.querySelectorAll("[name]").forEach(a=>{a.addEventListener("change",()=>{i()})}),e.root.querySelectorAll("[data-action-id]").forEach(a=>{a.addEventListener("click",()=>{e.pushEvent(a.dataset.actionId,{})})})},p=(a=r)=>{var m;r=a;let s=r.fields.map(d=>{var k;return x(d,(k=r.values[d.name])!=null?k:"")}).join(""),l=((m=r.actions)!=null?m:[]).map(d=>`<button type="button" class="kino-ethercat-explorer__action" data-action-id="${t(d.id)}">${t(d.label)}</button>`).join(""),h=r.description?`<div class="kino-ethercat-explorer__description">${t(r.description)}</div>`:"";e.root.innerHTML=`
      <div class="kino-ethercat-explorer">
        <div class="kino-ethercat-explorer__header">
          <div class="kino-ethercat-explorer__header-main">
            <h3 class="kino-ethercat-explorer__title">${t(r.title)}</h3>
            ${h}
          </div>
          <div class="kino-ethercat-explorer__actions">${l}</div>
        </div>
        <div class="kino-ethercat-explorer__grid">${s}</div>
      </div>
    `,c()};e.handleEvent("snapshot",p),e.handleSync(()=>{let a=document.activeElement;a&&e.root.contains(a)?a.dispatchEvent(new Event("change",{bubbles:!0})):i()}),p(o)}export{$ as init};
