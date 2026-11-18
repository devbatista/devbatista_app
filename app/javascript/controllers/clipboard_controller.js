import { Controller } from "@hotwired/stimulus"

// Copia o texto de um campo (Pix copia e cola, link da fatura) e confirma no próprio botão.
//
//   <div data-controller="clipboard">
//     <input data-clipboard-target="source" value="..." readonly>
//     <button data-action="clipboard#copy" data-clipboard-target="button">Copiar</button>
//   </div>
export default class extends Controller {
  static targets = ["source", "button"]

  async copy() {
    const text = this.sourceTarget.value || this.sourceTarget.textContent
    try {
      await navigator.clipboard.writeText(text)
    } catch {
      this.sourceTarget.select?.()
      document.execCommand("copy")
    }
    if (!this.hasButtonTarget) return

    const label = this.buttonTarget.dataset.label || this.buttonTarget.textContent
    this.buttonTarget.dataset.label = label
    this.buttonTarget.textContent = "Copiado"
    clearTimeout(this.timer)
    this.timer = setTimeout(() => { this.buttonTarget.textContent = label }, 2000)
  }
}
