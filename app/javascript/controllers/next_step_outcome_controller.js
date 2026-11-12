import { Controller } from "@hotwired/stimulus"

// Gaveta "Feito" da lista Próximos passos: mostra só os campos da saída escolhida (próximo passo
// ou perdido) e desliga os da outra, para o `required` dela não travar o envio.
export default class extends Controller {
  static targets = ["panel"]

  connect() { this.toggle() }

  toggle() {
    const chosen = this.element.querySelector("input[name$='[outcome]']:checked")?.value
    this.panelTargets.forEach((panel) => {
      const on = panel.dataset.outcome === chosen
      panel.hidden = !on
      panel.querySelectorAll("input, select, textarea").forEach((field) => { field.disabled = !on })
    })
  }
}
