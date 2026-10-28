import { Controller } from "@hotwired/stimulus"

// Recarrega um turbo-frame a cada intervalo enquanto houver algo em andamento dentro dele
// (elemento com data-refresh-busy). Para quando nada mais estiver em andamento e não recarrega
// com um campo em foco, para não apagar o que a pessoa está digitando.
//
//   <turbo-frame id="x" data-controller="refresh" data-refresh-url-value="/pagina">
export default class extends Controller {
  static values = { url: String, interval: { type: Number, default: 5000 } }

  connect() {
    this.schedule = this.schedule.bind(this)
    this.element.addEventListener("turbo:frame-load", this.schedule)
    this.schedule()
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-load", this.schedule)
    clearTimeout(this.timer)
  }

  schedule() {
    clearTimeout(this.timer)
    if (this.element.querySelector("[data-refresh-busy]")) this.timer = setTimeout(() => this.tick(), this.intervalValue)
  }

  tick() {
    if (this.element.contains(document.activeElement) && document.activeElement.matches("input, textarea, select")) return this.schedule()
    if (this.element.src) this.element.reload()
    else this.element.src = this.urlValue
  }
}
