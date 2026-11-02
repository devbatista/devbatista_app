import { Controller } from "@hotwired/stimulus"

// Planta do escritório de agentes (docs/specs/escritorio-agentes). Marca a sala do agente aberto no
// painel, inclusive depois que o tempo real redesenha o cartão (deskTargetConnected).
//
//   <div data-controller="escritorio" data-escritorio-selected-value="ops">
export default class extends Controller {
  static targets = ["desk"]
  static values = { selected: String }

  select(event) {
    this.selectedValue = event.currentTarget.dataset.agentKey
  }

  selectedValueChanged() {
    this.deskTargets.forEach((desk) => this.mark(desk))
  }

  deskTargetConnected(desk) {
    this.mark(desk)
  }

  mark(desk) {
    const on = desk.dataset.agentKey === this.selectedValue
    desk.classList.toggle("on", on)
    if (on) desk.setAttribute("aria-current", "true")
    else desk.removeAttribute("aria-current")
  }
}
