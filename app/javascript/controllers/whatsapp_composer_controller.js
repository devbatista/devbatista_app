import { Controller } from "@hotwired/stimulus"

// Campo de envio da conversa (docs/specs/whatsapp, Fase 6).
// - Texto: Enter envia, Shift+Enter quebra a linha; anexo conferido pelo tipo e pelo tamanho antes
//   de enviar (os mesmos limites do servidor); "Responder" cita a mensagem.
// - Template (janela aberta ou fechada): campos para cada variável e prévia como o contato vê.
// O modo que não está em uso fica num fieldset desabilitado, que não vai no envio. O servidor
// confere tudo de novo. Quando a janela fecha com a tela aberta, a conversa é recarregada.
const escape = (text) => String(text).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]))
const size = (bytes) => bytes >= 1048576 ? `${Math.round(bytes / 1048576)} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB`

export default class extends Controller {
  static targets = [ "kind", "problem", "textMode", "closedMode", "templateMode", "replyChip", "replyText", "replyTo", "body", "counter",
    "file", "fileChip", "fileName", "template", "variables", "headerFileField", "headerFile", "preview", "submit" ]
  static values = { open: Boolean, closesAt: Number, templates: Array, types: Object, limits: Object, labels: Object }

  connect() {
    this.count()
    if (this.openValue && this.closesAtValue) {
      this.closeTimer = setTimeout(() => window.Turbo.visit(window.location.href, { frame: "whatsapp_conversation" }), this.closesAtValue - Date.now() + 1000)
    }
  }

  disconnect() {
    clearTimeout(this.closeTimer)
  }

  keydown(event) {
    if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
      event.preventDefault()
      this.element.requestSubmit()
    }
  }

  count() {
    if (this.hasCounterTarget) this.counterTarget.textContent = `${this.bodyTarget.value.length}/${this.bodyTarget.maxLength}`
  }

  // ---------- Anexo ----------

  pickFile() {
    const file = this.fileTarget.files[0]
    this.problem("")
    if (!file) return this.removeFile()

    const kind = Object.keys(this.typesValue).find((k) => this.typesValue[k].includes(file.type))
    if (!kind) return this.rejectFile(`O WhatsApp não aceita esse tipo de arquivo (${file.type || "desconhecido"}).`)
    if (file.size > this.limitsValue[kind]) {
      return this.rejectFile(`O arquivo tem ${size(file.size)} e passa do limite de ${size(this.limitsValue[kind])} para ${this.labelsValue[kind]}.`)
    }
    this.fileChipTarget.hidden = false
    this.fileNameTarget.textContent = `${file.name} · ${size(file.size)}${[ "image", "video", "document" ].includes(kind) ? " · o texto vai como legenda" : ""}`
  }

  rejectFile(message) {
    this.removeFile()
    this.problem(message)
  }

  removeFile() {
    this.fileTarget.value = ""
    this.fileChipTarget.hidden = true
  }

  // ---------- Resposta ----------

  reply({ detail }) {
    if (!this.hasReplyToTarget) return
    if (!this.textModeTarget.disabled) {
      this.replyToTarget.value = detail.id
      this.replyTextTarget.textContent = `Respondendo: ${detail.text}`
      this.replyChipTarget.hidden = false
      this.bodyTarget.focus()
    }
  }

  cancelReply() {
    this.replyToTarget.value = ""
    this.replyChipTarget.hidden = true
  }

  // ---------- Modos ----------

  useTemplate() {
    this.mode("template")
    this.pickTemplate()
  }

  useText() {
    this.mode(this.openValue ? "text" : "closed")
  }

  mode(name) {
    this.problem("")
    this.kindTarget.value = name === "template" ? "template" : "text"
    this.textModeTarget.hidden = this.textModeTarget.disabled = name !== "text"
    this.templateModeTarget.hidden = this.templateModeTarget.disabled = name !== "template"
    if (this.hasClosedModeTarget) this.closedModeTarget.hidden = name !== "closed"
  }

  // ---------- Template ----------

  get selected() {
    return this.templatesValue.find((t) => String(t.id) === this.templateTarget.value)
  }

  pickTemplate() {
    if (!this.hasTemplateTarget) return
    const t = this.selected
    const fields = []
    if (t.header_text) fields.push(this.field("values[header][]", "Cabeçalho {{1}}"))
    t.body_names.forEach((name) => fields.push(this.field("values[body][]", `{{${name}}}`)))
    t.url_buttons.forEach((index) => fields.push(this.field(`values[buttons][${index}]`, `Fim do link: ${t.buttons[index].text}`)))
    this.variablesTarget.innerHTML = fields.join("")
    this.variablesTarget.querySelectorAll("input").forEach((input) => input.addEventListener("input", () => this.paint()))
    this.headerFileFieldTarget.hidden = !t.header_media
    this.headerFileTarget.required = !!t.header_media
    this.headerFileTarget.accept = t.header_media ? this.typesValue[t.header_media].join(",") : ""
    this.paint()
  }

  field(name, label) {
    return `<div class="field"><label>${escape(label)} <span class="req">*</span></label><input class="input" name="${name}" required autocomplete="off"></div>`
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

  // ---------- Envio ----------

  sending() {
    this.submitTargets.forEach((button) => { button.disabled = true })
  }

  sent() {
    this.submitTargets.forEach((button) => { button.disabled = false })
  }

  problem(message) {
    this.problemTarget.textContent = message
    this.problemTarget.hidden = !message
  }
}
