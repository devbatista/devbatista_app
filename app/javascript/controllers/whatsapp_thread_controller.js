import { Controller } from "@hotwired/stimulus"

// Linha do tempo da conversa aberta (docs/specs/whatsapp, Fase 6):
// - abre na última mensagem e acompanha as novas quando a pessoa já está no fim;
// - ao carregar as anteriores (turbo-frame no topo), mantém a posição da leitura;
// - mensagem recebida com a aba visível marca a conversa como lida (uma chamada, logo depois);
//   com a aba escondida, marca quando ela voltar a ficar visível;
// - "Responder" avisa o campo de envio (evento whatsapp:reply).
const NEAR_BOTTOM = 120
const READ_WAIT = 800

export default class extends Controller {
  static targets = [ "scroller", "thread" ]
  static values = { readUrl: String }

  connect() {
    this.toBottom()
    this.seen = new Set([ ...this.threadTarget.querySelectorAll(".msg-row") ].map((row) => row.id))
    this.observer = new MutationObserver((mutations) => this.added(mutations))
    this.observer.observe(this.threadTarget, { childList: true })
    this.onVisible = () => { if (document.visibilityState === "visible" && this.unread) this.markRead() }
    document.addEventListener("visibilitychange", this.onVisible)
    this.beforeOlder = (event) => { if (event.target.classList.contains("older")) this.heightBefore = this.scrollerTarget.scrollHeight }
    this.afterOlder = (event) => {
      if (!event.target.classList.contains("older") || this.heightBefore == null) return
      this.scrollerTarget.scrollTop += this.scrollerTarget.scrollHeight - this.heightBefore
      this.heightBefore = null
    }
    this.element.addEventListener("turbo:before-frame-render", this.beforeOlder)
    this.element.addEventListener("turbo:frame-render", this.afterOlder)
  }

  disconnect() {
    this.observer.disconnect()
    document.removeEventListener("visibilitychange", this.onVisible)
    this.element.removeEventListener("turbo:before-frame-render", this.beforeOlder)
    this.element.removeEventListener("turbo:frame-render", this.afterOlder)
    clearTimeout(this.readTimer)
  }

  // Mensagens que entraram no fim da linha do tempo (broadcast ou resposta do envio). Balão
  // substituído (status, mídia baixada) tem o mesmo id e não conta como novo.
  added(mutations) {
    const rows = mutations.flatMap((m) => [ ...m.addedNodes ])
      .filter((node) => node.classList?.contains("msg-row") && !this.seen.has(node.id))
    rows.forEach((row) => this.seen.add(row.id))
    if (!rows.length) return

    const ownMessage = rows.some((row) => row.querySelector(".msg.out"))
    if (ownMessage || this.nearBottom) this.toBottom()
    if (rows.some((row) => row.querySelector(".msg.client"))) {
      this.unread = true
      if (document.visibilityState === "visible") this.markRead()
    }
  }

  get nearBottom() {
    const s = this.scrollerTarget
    return s.scrollHeight - s.scrollTop - s.clientHeight < NEAR_BOTTOM
  }

  toBottom() {
    this.scrollerTarget.scrollTop = this.scrollerTarget.scrollHeight
  }

  markRead() {
    clearTimeout(this.readTimer)
    this.readTimer = setTimeout(() => {
      this.unread = false
      fetch(this.readUrlValue, { method: "POST", credentials: "same-origin", headers: { "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content } })
    }, READ_WAIT)
  }

  reply(event) {
    const { replyId, replyText } = event.currentTarget.dataset
    window.dispatchEvent(new CustomEvent("whatsapp:reply", { detail: { id: replyId, text: replyText } }))
  }
}
