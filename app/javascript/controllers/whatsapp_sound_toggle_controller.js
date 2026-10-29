import { Controller } from "@hotwired/stimulus"
import { storage, soundOn } from "controllers/whatsapp_alerts_controller"

// "Som dos avisos" no menu do usuário (Fase 8): liga e desliga o som dos avisos do WhatsApp neste
// navegador (localStorage "wa-som").
export default class extends Controller {
  static targets = [ "state" ]

  connect() {
    this.render()
  }

  toggle() {
    storage.set("wa-som", soundOn() ? "off" : "on")
    this.render()
  }

  render() {
    const on = soundOn()
    this.stateTarget.textContent = on ? "ligado" : "desligado"
    this.element.setAttribute("aria-pressed", on)
  }
}
