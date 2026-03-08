function t(e){return String(e!=null?e:"").replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;").replaceAll('"',"&quot;").replaceAll("'","&#39;")}function _(e,o){return e.map(r=>{let n=t(r.value),i=t(r.label),c=r.value===o?" selected":"";return`<option value="${n}"${c}>${i}</option>`}).join("")}function x(e){return e.map(o=>`<option value="${t(o.value)}">${t(o.label)}</option>`).join("")}function b(e,o){var i,c,p,a,s;let r=`field-${e.name}`,n=e.help?`<div class="kino-ethercat-explorer__help">${t(e.help)}</div>`:"";if(e.type==="select")return`
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
          ${x((a=e.options)!=null?a:[])}
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
  `}async function $(e,o){await e.importCSS("main.css");let r=o,n=()=>{var s;let a={};for(let l of r.fields){let d=e.root.querySelector(`[name="${l.name}"]`);a[l.name]=d?d.value:(s=r.values[l.name])!=null?s:""}return a},i=()=>e.pushEvent("update",n()),c=()=>{e.root.querySelectorAll("[name]").forEach(a=>{a.addEventListener("change",()=>{i()})}),e.root.querySelectorAll("[data-action-id]").forEach(a=>{a.addEventListener("click",()=>{e.pushEvent(a.dataset.actionId,{})})})},p=(a=r)=>{var d;r=a;let s=r.fields.map(h=>{var m;return b(h,(m=r.values[h.name])!=null?m:"")}).join(""),l=((d=r.actions)!=null?d:[]).map(h=>`<button type="button" class="kino-ethercat-explorer__action" data-action-id="${t(h.id)}">${t(h.label)}</button>`).join("");e.root.innerHTML=`
      <div class="kino-ethercat-explorer">
        <div class="kino-ethercat-explorer__header">
          <div>
            <div class="kino-ethercat-explorer__eyebrow">Smart Cell</div>
            <h3 class="kino-ethercat-explorer__title">${t(r.title)}</h3>
          </div>
          <div class="kino-ethercat-explorer__actions">${l}</div>
        </div>
        <p class="kino-ethercat-explorer__description">${t(r.description)}</p>
        <div class="kino-ethercat-explorer__grid">${s}</div>
      </div>
    `,c()};e.handleEvent("snapshot",p),e.handleSync(()=>{let a=document.activeElement;a&&e.root.contains(a)?a.dispatchEvent(new Event("change",{bubbles:!0})):i()}),p(o)}export{$ as init};
