import { Controller } from "@hotwired/stimulus"

// Template aprovado (docs/specs/whatsapp, Fases 6 e 7b), no campo de envio da conversa e no
// "Iniciar conversa": um campo por variável, a mídia do cabeçalho e a prévia como o contato vê.
// Os campos já vêm com os valores sugeridos pelo servidor (template.defaults: o {{1}} com o
// primeiro nome do lead ou contato, por exemplo), e todos podem ser editados. O servidor confere
// tudo de novo no envio.
const escape = (text) => String(text).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]))

export default class extends Controller {
  static targets = [ "template", "variables", "headerFileField", "headerFile", "preview" ]
  static values = { templates: Array, types: Object, labels: Object }

  connect() {
    this.pick()
  }

  get selected() {
    return this.templatesValue.find((t) => String(t.id) === this.templateTarget.value)
  }

  pick() {
    if (!this.hasTemplateTarget) return
    const t = this.selected
    const defaults = t.defaults || {}
    const fields = []
    if (t.header_text) fields.push(this.field("values[header][]", "Cabeçalho {{1}}", (defaults.header || [])[0]))
    t.body_names.forEach((name, i) => fields.push(this.field("values[body][]", `{{${name}}}`, (defaults.body || [])[i])))
    t.url_buttons.forEach((index) => fields.push(this.field(`values[buttons][${index}]`, `Fim do link: ${t.buttons[index].text}`, (defaults.buttons || {})[index])))
    this.variablesTarget.innerHTML = fields.join("")
    this.variablesTarget.querySelectorAll("input").forEach((input) => input.addEventListener("input", () => this.paint()))
    this.headerFileFieldTarget.hidden = !t.header_media
    this.headerFileTarget.required = !!t.header_media
    this.headerFileTarget.accept = t.header_media ? this.typesValue[t.header_media].join(",") : ""
    this.paint()
  }

  field(name, label, value) {
    return `<div class="field"><label>${escape(label)} <span class="req">*</span></label>` +
      `<input class="input" name="${name}" value="${escape(value || "")}" required autocomplete="off"></div>`
  }

  paint() {
    const t = this.selected
    const values = [ ...this.variablesTarget.querySelectorAll("input[name='values[body][]']") ].map((input) => input.value)
    const header = this.variablesTarget.querySelector("input[name='values[header][]']")?.value
    const fill = (text, names, vals) => escape(text).replace(/\{\{\s*(\w+)\s*\}\}/g, (match, name) => {
      const value = vals[names.indexOf(name)]
      return `<mark>${escape(value || match)}</mark>`
    })
    let html = ""
    if (t.header_media) html += `<div class="media-ph">${escape(this.labelsValue[t.header_media])} do cabeçalho</div>`
    if (t.header_text) html += `<b>${fill(t.header_text, [ "1" ], [ header ])}</b>`
    html += `<p>${fill(t.body, t.body_names, values)}</p>`
    if (t.footer) html += `<div class="ft">${escape(t.footer)}</div>`
    if (t.buttons.length) html += `<div class="tpl-btns">${t.buttons.map((b) => `<span>${escape(b.text)}</span>`).join("")}</div>`
    this.previewTarget.innerHTML = html
  }
}
