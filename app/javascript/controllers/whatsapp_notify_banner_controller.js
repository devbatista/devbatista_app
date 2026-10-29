import { Controller } from "@hotwired/stimulus"
import { storage } from "controllers/whatsapp_alerts_controller"

// Faixa "Ativar avisos" da tela de conversas (docs/design/whatsapp/conversas.html; Fase 8).
// - Aparece até a pessoa escolher "Ativar avisos" ou "Agora não" (localStorage "wa-avisos") e
//   enquanto o navegador não deu nem negou a permissão.
// - A permissão é pedida só no clique de "Ativar avisos".
// - Bloqueado pelo navegador: sobra só a linha que explica como reativar pelo cadeado.
export default class extends Controller {
  static targets = [ "bar", "blocked" ]

  connect() {
    this.choice = storage.get("wa-avisos")
    this.render()
  }

  get permission() {
    return "Notification" in window ? Notification.permission : "unsupported"
  }

  render() {
    this.blockedTarget.hidden = !(this.denied || this.permission === "denied")
    this.barTarget.hidden = this.permission !== "default" || !!this.choice
  }

  enable() {
    this.choose("ativado")
    Notification.requestPermission().then((result) => {
      this.denied = result === "denied"
      if (result === "granted") new Notification("Avisos do WhatsApp ativados", { body: "Você vai ser avisado quando chegar mensagem, mesmo em outra aba.", tag: "whatsapp-ativado" })
      this.render()
    })
  }

  dismiss() {
    this.choose("dispensado")
  }

  choose(value) {
    this.choice = value
    storage.set("wa-avisos", value)
    this.render()
  }
}
