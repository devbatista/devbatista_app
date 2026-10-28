import { Controller } from "@hotwired/stimulus"

// Conexão de um número pelo Embedded Signup da Meta, versão 5 (docs/specs/whatsapp, Fase 4).
//
// Carrega o SDK do Facebook só nesta tela e abre a janela da Meta (FB.login). A janela manda o
// session info por postMessage (WA_EMBEDDED_SIGNUP) e o callback do FB.login traz o code, que
// vale 30 segundos. Com os dois, envia ao servidor. Se o session info não chegar em 5 s, envia só
// o code e o servidor descobre a WABA e o número. O code nunca vai para o console.
const SDK_URL = "https://connect.facebook.net/en_US/sdk.js"
const SESSION_WAIT = 5000
// FINISH na v5; FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING é a coexistência na v4.
const FINISH_EVENTS = [ "FINISH", "FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING" ]
const TONES = { info: "callout", good: "callout", warn: "callout warn", crit: "callout crit" }

let sdk // carregamento do SDK, uma vez por sessão do navegador (o Turbo mantém o módulo)

const loadSdk = (appId, version) => {
  sdk ||= new Promise((resolve, reject) => {
    window.fbAsyncInit = () => {
      window.FB.init({ appId, autoLogAppEvents: true, xfbml: true, version })
      resolve(window.FB)
    }
    const script = document.createElement("script")
    script.src = SDK_URL
    script.async = true
    script.defer = true
    script.crossOrigin = "anonymous"
    script.onerror = () => { sdk = null; reject(new Error("sdk")) }
    document.head.appendChild(script)
  })
  return sdk
}

// Só mensagens de facebook.com (ou subdomínio) por https.
const fromFacebook = (origin) => {
  try {
    const url = new URL(origin)
    return url.protocol === "https:" && (url.hostname === "facebook.com" || url.hostname.endsWith(".facebook.com"))
  } catch {
    return false
  }
}

export default class extends Controller {
  static targets = [ "button", "status" ]
  static values = { appId: String, configId: String, version: String, connectUrl: String, eventUrl: String }

  connect() {
    this.onMessage = this.onMessage.bind(this)
    window.addEventListener("message", this.onMessage)
    if (!this.configIdValue) return // falta configuração: o botão fica desabilitado

    loadSdk(this.appIdValue, this.versionValue)
      .then(() => { this.buttonTarget.disabled = false })
      .catch(() => this.show("Não foi possível carregar o SDK da Meta. Confira a conexão e recarregue a página.", "crit"))
  }

  disconnect() {
    window.removeEventListener("message", this.onMessage)
    clearTimeout(this.timer)
  }

  launch() {
    this.code = null
    this.session = null
    this.cancelled = false
    this.submitting = false
    this.buttonTarget.disabled = true
    this.show("Conclua as etapas na janela da Meta…")
    window.FB.login((response) => this.onLogin(response), {
      config_id: this.configIdValue,
      response_type: "code",
      override_default_response_type: true,
      extras: { version: "v5" }
    })
  }

  onLogin(response) {
    const code = response?.authResponse?.code
    if (!code) {
      if (!this.cancelled) this.show("A conexão foi cancelada antes do fim. Nada foi alterado.", "warn")
      this.buttonTarget.disabled = false
      return
    }
    this.code = code
    this.show("Conectando…")
    if (this.session) this.submit()
    else this.timer = setTimeout(() => this.submit(), SESSION_WAIT)
  }

  onMessage(event) {
    if (!fromFacebook(event.origin)) return
    let message
    try {
      message = typeof event.data === "string" ? JSON.parse(event.data) : event.data
    } catch {
      return
    }
    if (message?.type !== "WA_EMBEDDED_SIGNUP") return

    const data = message.data || {}
    if (FINISH_EVENTS.includes(message.event)) {
      this.session = {
        phone_number_id: data.phone_number_id,
        waba_id: data.messaging_account_ids?.[0] || data.waba_id,
        business_id: data.business_id,
        is_on_biz_app: message.event === "FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING" ? true : data.is_on_biz_app
      }
      if (this.code) this.submit()
    } else if (message.event === "CANCEL") {
      this.cancelled = true
      const where = data.current_step ? ` no passo ${data.current_step}` : ""
      this.show(data.error_message ? `A Meta informou um erro${where}: ${data.error_message}` : `A janela da Meta foi fechada${where}, antes do fim. Nada foi alterado.`, "warn")
      // Só para o log do servidor: passo, código do erro e sessão, sem a mensagem.
      this.post(this.eventUrlValue, { current_step: data.current_step, error_code: data.error_code, session_id: data.session_id }).catch(() => {})
    }
  }

  async submit() {
    if (this.submitting || !this.code) return
    this.submitting = true
    clearTimeout(this.timer)
    const code = this.code
    this.code = null
    this.show("Conectando…")
    try {
      const response = await this.post(this.connectUrlValue, { code, ...this.session })
      const body = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(body.error || "Não foi possível conectar. Tente de novo.")

      this.show(body.message, "good")
      window.Turbo.visit(body.url, { action: "replace" })
    } catch (error) {
      this.show(error instanceof TypeError ? "Sem resposta do Admin. Confira a conexão e tente de novo." : error.message, "crit")
      this.buttonTarget.disabled = false
    }
  }

  post(url, body) {
    return fetch(url, {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content },
      body: JSON.stringify(body)
    })
  }

  show(text, tone = "info") {
    this.statusTarget.hidden = false
    this.statusTarget.className = TONES[tone]
    this.statusTarget.textContent = text
  }
}
