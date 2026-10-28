import { Controller } from "@hotwired/stimulus"

// Campo de envio da conversa (docs/specs/whatsapp, Fase 6).
// - Texto: Enter envia, Shift+Enter quebra a linha; anexo conferido pelo tipo e pelo tamanho antes
//   de enviar (os mesmos limites do servidor); "Responder" cita a mensagem.
// - Template (janela aberta ou fechada): os campos e a prévia ficam no controller
//   whatsapp-template-fields, dentro do modo template.
// O modo que não está em uso fica num fieldset desabilitado, que não vai no envio. O servidor
// confere tudo de novo. Quando a janela fecha com a tela aberta, a conversa é recarregada.
const size = (bytes) => bytes >= 1048576 ? `${Math.round(bytes / 1048576)} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB`

export default class extends Controller {
  static targets = [ "kind", "problem", "textMode", "closedMode", "templateMode", "replyChip", "replyText", "replyTo", "body", "counter",
    "file", "fileChip", "fileName", "submit" ]
  static values = { open: Boolean, closesAt: Number, types: Object, limits: Object, labels: Object }

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
