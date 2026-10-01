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

const closeAll = () => {
  document.querySelectorAll(".drawer.open, .modal.open, .popover.open").forEach((el) => el.classList.remove("open"))
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
    if (el) { e.preventDefault(); openPanel(el) }
    return
  }

  if (t.closest("[data-close]") || t.closest("[data-overlay]")) { closeAll(); return }

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

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") { closeAll(); document.body.classList.remove("nav-open") }
})

document.addEventListener("turbo:load", filterCounts)
// Fecha painéis abertos antes de o Turbo guardar a página no cache.
document.addEventListener("turbo:before-cache", () => { closeAll(); document.body.classList.remove("nav-open") })
