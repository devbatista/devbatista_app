import { Controller } from "@hotwired/stimulus"

// Chave Pix nas Configurações (docs/specs/faturas): máscara pelo tipo escolhido e validação no
// navegador, com a mesma regra do servidor (PixKey). Chave com dígito errado é recusada antes de
// salvar: no app do banco ela aparece como "chave inexistente".
//
//   <div data-controller="pix-key">
//     <select data-pix-key-target="type" data-action="pix-key#change">…</select>
//     <input data-pix-key-target="input" data-action="input->pix-key#format blur->pix-key#check">
//     <span data-pix-key-target="hint"></span>
//   </div>
const digits = (value) => value.replace(/\D/g, "")

// Dígito verificador módulo 11 (CPF e CNPJ).
const checkDigit = (numbers, weights) => {
  const rest = numbers.reduce((sum, n, i) => sum + n * weights[i], 0) % 11
  return rest < 2 ? 0 : 11 - rest
}

const validCpf = (value) => {
  const d = digits(value)
  if (d.length !== 11 || /^(\d)\1+$/.test(d)) return false
  const n = [ ...d ].map(Number)
  const w = (size) => Array.from({ length: size }, (_, i) => size + 1 - i)
  return checkDigit(n.slice(0, 9), w(9)) === n[9] && checkDigit(n.slice(0, 10), w(10)) === n[10]
}

const validCnpj = (value) => {
  const d = digits(value)
  if (d.length !== 14 || /^(\d)\1+$/.test(d)) return false
  const n = [ ...d ].map(Number)
  const w1 = [ 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2 ]
  return checkDigit(n.slice(0, 12), w1) === n[12] && checkDigit(n.slice(0, 13), [ 6, ...w1 ]) === n[13]
}

const TYPES = {
  cnpj: {
    placeholder: "00.000.000/0000-00", inputmode: "numeric",
    hint: "CNPJ cadastrado como chave na conta do banco",
    mask: (v) => digits(v).slice(0, 14).replace(/^(\d{2})(\d)/, "$1.$2").replace(/^(\d{2})\.(\d{3})(\d)/, "$1.$2.$3")
      .replace(/\.(\d{3})(\d)/, ".$1/$2").replace(/(\d{4})(\d)/, "$1-$2"),
    error: (v) => (validCnpj(v) ? null : "CNPJ inválido: confira os dígitos")
  },
  cpf: {
    placeholder: "000.000.000-00", inputmode: "numeric",
    hint: "CPF cadastrado como chave na conta do banco",
    mask: (v) => digits(v).slice(0, 11).replace(/^(\d{3})(\d)/, "$1.$2").replace(/^(\d{3})\.(\d{3})(\d)/, "$1.$2.$3")
      .replace(/\.(\d{3})(\d)/, ".$1-$2"),
    error: (v) => (validCpf(v) ? null : "CPF inválido: confira os dígitos")
  },
  phone: {
    placeholder: "(11) 98765-4321", inputmode: "tel",
    hint: "Celular com DDD. Vai para o banco como +55",
    mask: (v) => {
      const d = digits(v).replace(/^55(?=\d{10,11}$)/, "").slice(0, 11)
      if (d.length <= 2) return d.length ? `(${d}` : ""
      const split = d.length === 11 ? 7 : 6
      return `(${d.slice(0, 2)}) ${d.slice(2, split)}${d.length > split ? "-" + d.slice(split) : ""}`
    },
    error: (v) => ([ 10, 11 ].includes(digits(v).replace(/^55(?=\d{10,11}$)/, "").length) ? null : "Celular precisa ter DDD e número")
  },
  email: {
    placeholder: "pix@empresa.com.br", inputmode: "email",
    hint: "E-mail cadastrado como chave na conta do banco",
    mask: (v) => v.trim().toLowerCase(),
    error: (v) => (/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v) && v.length <= 77 ? null : "E-mail inválido")
  },
  random: {
    placeholder: "123e4567-e89b-12d3-a456-426614174000", inputmode: "text",
    hint: "Chave aleatória: 32 letras e números, no formato que o banco mostra",
    mask: (v) => {
      const h = v.toLowerCase().replace(/[^0-9a-f]/g, "").slice(0, 32)
      return [ h.slice(0, 8), h.slice(8, 12), h.slice(12, 16), h.slice(16, 20), h.slice(20) ].filter(Boolean).join("-")
    },
    error: (v) => (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(v) ? null : "Chave aleatória incompleta")
  }
}

export default class extends Controller {
  static targets = [ "type", "input", "hint" ]

  connect() {
    this.apply(false)
  }

  get kind() {
    return TYPES[this.typeTarget.value] || TYPES.cnpj
  }

  // Trocar o tipo limpa a chave: o que vale para um tipo não vale para o outro.
  change() {
    this.inputTarget.value = ""
    this.apply(false)
    this.inputTarget.focus()
  }

  format() {
    this.inputTarget.value = this.kind.mask(this.inputTarget.value)
    if (this.inputTarget.dataset.checked) this.check()
  }

  check() {
    this.inputTarget.dataset.checked = "1"
    const value = this.inputTarget.value
    const error = value ? this.kind.error(value) : null
    this.inputTarget.setCustomValidity(error || "")
    this.inputTarget.classList.toggle("invalid", !!error)
    this.inputTarget.setAttribute("aria-invalid", error ? "true" : "false")
    this.hintTarget.textContent = error || this.kind.hint
    this.hintTarget.style.color = error ? "var(--crit)" : ""
  }

  apply(validate) {
    const kind = this.kind
    this.inputTarget.placeholder = kind.placeholder
    this.inputTarget.inputMode = kind.inputmode
    if (this.inputTarget.value) this.inputTarget.value = kind.mask(this.inputTarget.value)
    delete this.inputTarget.dataset.checked
    this.hintTarget.textContent = kind.hint
    this.hintTarget.style.color = ""
    this.inputTarget.setCustomValidity("")
    if (validate || this.inputTarget.value) this.check()
  }
}
