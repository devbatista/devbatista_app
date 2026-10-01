// Interações do design system (docs/design/DESIGN-SYSTEM.md), adaptadas ao Turbo.
// Os eventos são delegados ao document, então valem para qualquer página carregada pelo Turbo.
//
//   data-open="id" / data-close           abre e fecha .drawer e .modal
//   data-tabs > data-tab="x" + data-panel  abas
//   data-filter-group / data-filter / data-filter-target / data-status   filtro de linhas
//   data-popover-toggle="id"               abre e fecha um .popover
//   data-nav-toggle / data-nav-group       menu lateral no celular e grupos do menu
//   data-password-toggle                   mostra e oculta a senha

const overlay = () => document.querySelector("[data-overlay]")

const LOADING = '<div class="drawer-body caption">Carregando…</div>'

const closeAll = () => {
  document.querySelectorAll(".drawer.open, .modal.open, .popover.open").forEach((el) => el.classList.remove("open"))
  // Limpa a gaveta para o próximo formulário não mostrar o anterior.
  const frame = document.getElementById("drawer-frame")
  if (frame) { frame.removeAttribute("src"); frame.innerHTML = LOADING }
  document.querySelectorAll("[data-popover-toggle]").forEach((b) => b.setAttribute("aria-expanded", "false"))
  overlay()?.classList.remove("open")
}

const openPanel = (el) => {
  el.classList.add("open")
  overlay()?.classList.add("open")
  const field = el.querySelector("input:not([type=hidden]), select, textarea, button")
  if (field) setTimeout(() => field.focus(), 30)
}

const filterCounts = () => {
  document.querySelectorAll("[data-filter-group]").forEach((group) => {
    const target = document.querySelector(`[data-filter-target="${group.dataset.filterGroup}"]`)
    if (!target) return
    const rows = [...target.querySelectorAll("[data-status]")]
    group.querySelectorAll("button[data-filter]").forEach((b) => {
      const c = b.querySelector(".c")
      if (c) c.textContent = b.dataset.filter === "todos" ? rows.length : rows.filter((r) => r.dataset.status === b.dataset.filter).length
    })
  })
}

document.addEventListener("click", (e) => {
  const t = e.target

  const open = t.closest("[data-open]")
  if (open) {
    const el = document.getElementById(open.dataset.open)
    if (el) {
      // Links com data-turbo-frame carregam o conteúdo da gaveta; o Turbo cuida da navegação.
      if (!open.dataset.turboFrame) e.preventDefault()
      openPanel(el)
    }
    return
  }

  if (t.closest("[data-search-open]")) { openPalette(); return }

  const close = t.closest("[data-close]")
  if (close || t.closest("[data-overlay]")) {
    // Dentro da gaveta ou do modal, só fecha; numa página própria, o link segue normalmente.
    if (!close || close.closest(".drawer.open, .modal.open")) { e.preventDefault(); closeAll(); palette()?.classList.remove("open") }
    return
  }

  const pop = t.closest("[data-popover-toggle]")
  if (pop) {
    const el = document.getElementById(pop.dataset.popoverToggle)
    const willOpen = !el.classList.contains("open")
    closeAll()
    if (willOpen) { el.classList.add("open"); pop.setAttribute("aria-expanded", "true") }
    return
  }
  if (!t.closest(".popover")) document.querySelectorAll(".popover.open").forEach((el) => el.classList.remove("open"))

  if (t.closest("[data-nav-toggle]")) { document.body.classList.toggle("nav-open"); return }
  if (document.body.classList.contains("nav-open") && !t.closest(".side")) document.body.classList.remove("nav-open")

  const grp = t.closest("[data-nav-group]")
  if (grp) {
    grp.classList.toggle("open")
    grp.setAttribute("aria-expanded", grp.classList.contains("open"))
    return
  }

  const tab = t.closest("[data-tab]")
  if (tab) {
    const tabs = tab.closest("[data-tabs]")
    const scope = tabs.closest("[data-tabs-scope]") || document
    tabs.querySelectorAll("[data-tab]").forEach((x) => { x.classList.toggle("on", x === tab); x.setAttribute("aria-selected", x === tab) })
    scope.querySelectorAll("[data-panel]").forEach((p) => { p.hidden = p.dataset.panel !== tab.dataset.tab })
    return
  }

  const filter = t.closest("button[data-filter]")
  if (filter) {
    const group = filter.closest("[data-filter-group]")
    const target = document.querySelector(`[data-filter-target="${group.dataset.filterGroup}"]`)
    const v = filter.dataset.filter
    group.querySelectorAll("button[data-filter]").forEach((x) => { x.classList.toggle("on", x === filter); x.setAttribute("aria-pressed", x === filter) })
    target?.querySelectorAll("[data-status]").forEach((r) => { r.hidden = v !== "todos" && r.dataset.status !== v })
    return
  }

  const pw = t.closest("[data-password-toggle]")
  if (pw) {
    const input = pw.parentElement.querySelector("input")
    const show = input.type === "password"
    input.type = show ? "text" : "password"
    pw.setAttribute("aria-pressed", show)
    pw.setAttribute("aria-label", show ? "Ocultar senha" : "Mostrar senha")
    return
  }

  if (t.closest("[data-flash-close]")) t.closest("[data-flash]").remove()

  // Linhas de tabela clicáveis
  const row = t.closest("tr[data-href]")
  if (row && !t.closest("a, button, input, select, label")) Turbo.visit(row.dataset.href)
})

// Busca global (⌘K / Ctrl+K)
const palette = () => document.querySelector("[data-palette]")
const escapeHtml = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]))
let searchTimer, searchSeq = 0

const openPalette = () => {
  const p = palette()
  if (!p) return
  p.classList.add("open")
  overlay()?.classList.add("open")
  setTimeout(() => p.querySelector("[data-palette-input]").focus(), 10)
}

const renderResults = (groups, q) => {
  const box = palette().querySelector("[data-palette-results]")
  if (q.length < 2) { box.innerHTML = '<div class="palette-group">Digite pelo menos 2 letras</div>'; return }
  if (!groups.length) { box.innerHTML = '<div class="empty">Nada encontrado para essa busca.</div>'; return }
  box.innerHTML = groups.map((g) => `<div class="palette-group">${escapeHtml(g.label)}</div>` +
    g.items.map((i) => `<a class="palette-item" href="${escapeHtml(i.path)}"><span class="strong">${escapeHtml(i.title)}</span><span class="muted">${escapeHtml(i.subtitle || "")}</span></a>`).join("")).join("")
}

document.addEventListener("input", (e) => {
  if (!e.target.matches("[data-palette-input]")) return
  const q = e.target.value.trim()
  const all = palette().querySelector("[data-palette-all]")
  if (all) all.href = `${all.pathname}?q=${encodeURIComponent(q)}`
  clearTimeout(searchTimer)
  searchTimer = setTimeout(async () => {
    const seq = ++searchSeq
    if (q.length < 2) return renderResults([], q)
    const res = await fetch(`${palette().dataset.url}?q=${encodeURIComponent(q)}`, { headers: { Accept: "application/json" } })
    if (seq === searchSeq && res.ok) renderResults(await res.json(), q)
  }, 180)
})

document.addEventListener("keydown", (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") { e.preventDefault(); openPalette(); return }
  if (e.key === "Escape") { closeAll(); palette()?.classList.remove("open"); document.body.classList.remove("nav-open"); return }

  // Setas navegam pelos resultados da busca
  const p = palette()
  if (p?.classList.contains("open") && (e.key === "ArrowDown" || e.key === "ArrowUp")) {
    const items = [...p.querySelectorAll(".palette-item")]
    if (!items.length) return
    e.preventDefault()
    const i = items.indexOf(document.activeElement)
    const next = e.key === "ArrowDown" ? Math.min(i + 1, items.length - 1) : Math.max(i - 1, -1)
    next < 0 ? p.querySelector("[data-palette-input]").focus() : items[next].focus()
  }
})

document.addEventListener("turbo:load", filterCounts)

// Foco no primeiro campo quando o formulário chega na gaveta.
document.addEventListener("turbo:frame-load", (e) => {
  if (e.target.id !== "drawer-frame") return
  const field = e.target.querySelector("input:not([type=hidden]), select, textarea")
  if (field) field.focus()
})
// Fecha painéis abertos antes de o Turbo guardar a página no cache.
document.addEventListener("turbo:before-cache", () => { closeAll(); palette()?.classList.remove("open"); document.body.classList.remove("nav-open") })
