import { Controller } from "@hotwired/stimulus"

// Tela de conversas do WhatsApp (docs/specs/whatsapp, Fase 6): marca na lista a conversa aberta
// (também nos itens que chegam pelo broadcast), filtra e busca recarregando só a lista, e faz a
// navegação das telas estreitas (lista → conversa → painel).
const SEARCH_WAIT = 300

export default class extends Controller {
  static targets = [ "form", "filter", "list" ]
  static values = { selected: String }

  connect() {
    this.observer = new MutationObserver(() => this.highlight())
    this.observer.observe(this.listTarget, { childList: true, subtree: true })
    this.highlight()
  }

  disconnect() {
    this.observer.disconnect()
    clearTimeout(this.timer)
  }

  // Conversa aberta pela lista (turbo-frame "whatsapp_conversation").
  opened(event) {
    if (event.target.id !== "whatsapp_conversation") return

    this.selectedValue = event.target.querySelector("[data-conversation-id]")?.dataset.conversationId || ""
    this.element.classList.toggle("show-conv", !!this.selectedValue)
    this.closePanel()
  }

  selectedValueChanged() {
    this.highlight()
  }

  highlight() {
    if (!this.hasListTarget) return
    this.listTarget.querySelectorAll(".cv").forEach((item) => {
      const on = item.dataset.conversationId === this.selectedValue
      item.classList.toggle("on", on)
      on ? item.setAttribute("aria-current", "true") : item.removeAttribute("aria-current")
    })
  }

  search() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.formTarget.requestSubmit(), SEARCH_WAIT)
  }

  filterBy(event) {
    const button = event.currentTarget
    this.filterTarget.value = button.dataset.filter
    this.formTarget.querySelectorAll("[data-filter]").forEach((chip) => chip.setAttribute("aria-pressed", chip === button))
    this.formTarget.requestSubmit()
  }

  back() {
    this.element.classList.remove("show-conv")
  }

  togglePanel() {
    this.element.classList.toggle("panel-open")
  }

  closePanel() {
    this.element.classList.remove("panel-open")
  }
}
