import { Controller } from "@hotwired/stimulus"

// Aviso do navegador com som para mensagem recebida no WhatsApp (docs/specs/whatsapp, Fase 8), em
// todas as telas do Admin. Fica no layout, num elemento permanente entre as visitas do Turbo, junto
// do stream do usuário: o Whatsapp::Notifier acrescenta aqui um alvo "alert" (nome, prévia e endereço
// da conversa, como na central), que este controller lê e remove.
// - Não avisa se a conversa está aberta e a aba visível.
// - Várias abas: só uma avisa e toca (a candidata que ficar por último no localStorage).
// - O aviso usa a tag "whatsapp-<conversa>": o novo substitui o anterior da mesma conversa; o clique
//   foca a janela e abre a conversa.
// - O som só toca depois da primeira interação com a página (regra de autoplay dos navegadores) e
//   segue a opção "Som dos avisos" (whatsapp-sound-toggle). A permissão do navegador é pedida só no
//   clique de "Ativar avisos" (whatsapp-notify-banner), nunca aqui.
export const storage = {
  get(key) {
    try { return window.localStorage.getItem(key) } catch { return null }
  },
  set(key, value) {
    try { window.localStorage.setItem(key, value); return true } catch { return false }
  }
}

// Som ligado: escolha explícita ("on"/"off") ou, sem escolha, ligado para quem ativou os avisos.
export const soundOn = () => {
  const choice = storage.get("wa-som")
  return choice ? choice === "on" : storage.get("wa-avisos") === "ativado"
}

const CLAIM_KEY = "wa-aviso-ultimo"

export default class extends Controller {
  static targets = [ "alert" ]
  static values = { sound: String }

  connect() {
    this.tab = Math.random().toString(36).slice(2)
    this.unlock = () => { this.interacted = true }
    document.addEventListener("pointerdown", this.unlock, { capture: true })
    document.addEventListener("keydown", this.unlock, { capture: true })
  }

  disconnect() {
    document.removeEventListener("pointerdown", this.unlock, { capture: true })
    document.removeEventListener("keydown", this.unlock, { capture: true })
  }

  async alertTargetConnected(element) {
    const alert = { ...element.dataset }
    element.remove()
    if (this.conversationOnScreen(alert.conversationId)) return
    if (await this.claim(alert.messageId)) this.show(alert)
  }

  conversationOnScreen(id) {
    return document.visibilityState === "visible" && !!document.querySelector(`.conv[data-conversation-id="${CSS.escape(id)}"]`)
  }

  // Cada aba se candidata gravando a mensagem e o seu id; depois de um instante, avisa só a que
  // continua gravada. Sem localStorage, cada aba avisa (a tag evita aviso repetido na tela).
  async claim(messageId) {
    const current = storage.get(CLAIM_KEY)
    if (current && current.startsWith(`${messageId}:`)) return false

    const mine = `${messageId}:${this.tab}`
    if (!storage.set(CLAIM_KEY, mine)) return true
    await new Promise((resolve) => setTimeout(resolve, 150))
    return storage.get(CLAIM_KEY) === mine
  }

  show({ title, body, url, conversationId }) {
    if ("Notification" in window && Notification.permission === "granted") {
      const notification = new Notification(title, { body, tag: `whatsapp-${conversationId}` })
      notification.onclick = () => {
        window.focus()
        notification.close()
        window.Turbo ? window.Turbo.visit(url) : window.location.assign(url)
      }
    }
    this.play()
  }

  play() {
    if (!this.interacted || !this.soundValue || !soundOn()) return
    this.audio ||= new Audio(this.soundValue)
    this.audio.currentTime = 0
    this.audio.play().catch(() => {})
  }
}
