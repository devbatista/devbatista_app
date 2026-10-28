import { Controller } from "@hotwired/stimulus"

// Editor de template do WhatsApp (docs/specs/whatsapp, Fase 5): mostra os campos do tipo de
// cabeçalho e de cada botão, cria um campo de exemplo para cada variável do corpo e atualiza a
// prévia "como o contato vê" enquanto a pessoa digita. As regras valem no servidor
// (Whatsapp::TemplateBuilder); aqui é só o retorno imediato.
const MEDIA = { image: "Imagem", document: "Documento", video: "Vídeo" }
const ICONS = { url: "↗ ", phone: "☎ " }
const VARIABLE = /\{\{\s*(\d+)\s*\}\}/g

const escape = (text) => String(text).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]))
const numbers = (text) => [ ...new Set([ ...text.matchAll(VARIABLE) ].map((m) => Number(m[1]))) ].sort((a, b) => a - b)

export default class extends Controller {
  static targets = [ "headerType", "headerText", "headerTextField", "headerExampleField", "headerMediaField", "body", "counter",
    "examples", "examplesField", "footer", "buttons", "buttonTemplate", "buttonRow",
    "pvHeader", "pvMedia", "pvBody", "pvFooter", "pvButtons" ]

  connect() {
    this.refresh()
  }

  addVariable() {
    const body = this.bodyTarget
    const next = (numbers(body.value).at(-1) || 0) + 1
    const at = body.selectionStart ?? body.value.length
    body.value = `${body.value.slice(0, at)}{{${next}}}${body.value.slice(at)}`
    body.focus()
    body.setSelectionRange(at + `{{${next}}}`.length, at + `{{${next}}}`.length)
    this.refresh()
  }

  addButton() {
    this.buttonsTarget.appendChild(this.buttonTemplateTarget.content.cloneNode(true))
    this.refresh()
  }

  removeButton(event) {
    event.target.closest("[data-template-editor-target='buttonRow']").remove()
    this.refresh()
  }

  refresh() {
    const type = this.headerTypeTarget.value
    const headerText = this.headerTextTarget.value
    this.headerTextFieldTarget.hidden = type !== "text"
    this.headerExampleFieldTarget.hidden = type !== "text" || !numbers(headerText).length
    this.headerMediaFieldTarget.hidden = !MEDIA[type]
    this.counterTarget.textContent = `${this.bodyTarget.value.length}/1024`
    this.syncExamples()
    this.buttonRowTargets.forEach((row) => this.toggleButtonFields(row))
    this.preview(type, headerText)
  }

  // Um campo por variável, de {{1}} até a maior, mantendo o que já foi digitado.
  syncExamples() {
    const max = numbers(this.bodyTarget.value).at(-1) || 0
    const inputs = [ ...this.examplesTarget.querySelectorAll("input") ]
    this.examplesFieldTarget.hidden = max === 0
    if (inputs.length === max) return

    const values = inputs.map((input) => input.value)
    this.examplesTarget.innerHTML = Array.from({ length: max }, (_, i) => {
      const n = i + 1
      return `<div class="field"><label for="ex-${n}">Exemplo de {{${n}}}</label>` +
        `<input class="input" id="ex-${n}" name="template[body_examples][]" data-n="${n}" required value="${escape(values[i] || "")}"></div>`
    }).join("")
  }

  toggleButtonFields(row) {
    const type = row.querySelector("[data-role='type']").value
    const url = row.querySelector("[data-role='url']")
    url.hidden = type !== "url"
    row.querySelector("[data-role='phone']").hidden = type !== "phone"
    row.querySelector("[data-role='url_example']").hidden = type !== "url" || !numbers(url.value).length
  }

  preview(type, headerText) {
    const examples = [ ...this.examplesTarget.querySelectorAll("input") ].map((input) => input.value)
    const headerExample = this.headerExampleFieldTarget.querySelector("input")?.value
    this.pvHeaderTarget.hidden = type !== "text" || !headerText
    this.pvHeaderTarget.innerHTML = this.fill(headerText, [ headerExample ])
    this.pvMediaTarget.hidden = !MEDIA[type]
    this.pvMediaTarget.textContent = MEDIA[type] || ""
    this.pvBodyTarget.innerHTML = this.bodyTarget.value ? this.fill(this.bodyTarget.value, examples) : "O texto do corpo aparece aqui."
    this.pvFooterTarget.hidden = !this.footerTarget.value
    this.pvFooterTarget.textContent = this.footerTarget.value
    this.pvButtonsTarget.innerHTML = this.buttonRowTargets.map((row) => {
      const kind = row.querySelector("[data-role='type']").value
      const text = row.querySelector("[data-role='text']").value || "Botão"
      return `<span>${ICONS[kind] || ""}${escape(text)}</span>`
    }).join("")
  }

  fill(text, examples) {
    return escape(text).replace(VARIABLE, (_, n) => `<mark>${escape(examples[n - 1] || `{{${n}}}`)}</mark>`)
  }
}
