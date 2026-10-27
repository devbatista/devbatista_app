/* ==========================================================================
   Protótipo: diálogo "Iniciar conversa no WhatsApp" do lead, da empresa e do contato.
   O botão declara para quem é:
     data-wa-iniciar
     data-nome="Paulo Reis" data-org="Empresa ACME"
     data-numero="(11) 97654-1122"   vazio = sem WhatsApp cadastrado (o diálogo avisa e pede o número)
     data-cadastro="contato"         "lead" ou "contato"
     data-tpl="retomada_contato"     template sugerido
   Carregue depois do app.js. O primeiro contato é sempre por template aprovado.
   ========================================================================== */
(function () {
  'use strict';

  // Templates aprovados da conta (os mesmos de whatsapp/templates.html). {{1}} é sempre o primeiro nome.
  const TPL = {
    boas_vindas_lead: ['Utilidade', 'Olá, {{1}}! Aqui é o {{2}}, da DevBatista. Recebemos seu pedido de {{3}} pelo site. Podemos conversar por aqui?', ['Nome', 'Seu nome', 'Assunto'], ['', 'Rafael', 'diagnóstico']],
    retomada_contato: ['Marketing', 'Olá, {{1}}! Tudo bem? Passando para retomar nossa conversa sobre {{2}}. Posso te ajudar com algo por aqui?', ['Nome', 'Assunto'], ['', 'o seu projeto']],
    lembrete_reuniao: ['Utilidade', 'Olá, {{1}}. Lembrete da nossa reunião {{2}} às {{3}}. O link de acesso está no convite enviado por e-mail.', ['Nome', 'Data', 'Horário'], ['', 'de terça, 22/09', '10h']],
    proposta_enviada: ['Utilidade', 'Olá, {{1}}. Enviamos a proposta {{2}} para o seu e-mail. Ela é válida até {{3}}.', ['Nome', 'Proposta', 'Validade'], ['', '', '']],
    lembrete_proposta: ['Utilidade', 'Olá, {{1}}. A proposta {{2}} vence em {{3}}. Ficou alguma dúvida? Se quiser, ajusto algum ponto com você.', ['Nome', 'Proposta', 'Validade'], ['', '', '']]
  };
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const X = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg>';

  const modal = document.createElement('div');
  modal.className = 'modal';
  modal.id = 'iniciar-wa';
  modal.setAttribute('role', 'dialog');
  modal.setAttribute('aria-modal', 'true');
  modal.setAttribute('aria-labelledby', 'iniciar-wa-t');
  modal.innerHTML =
    '<form class="form" style="display:contents">' +
    `<div class="modal-head"><h2 id="iniciar-wa-t">Iniciar conversa no WhatsApp</h2><button class="icon-btn ghost" type="button" data-wa-fechar aria-label="Fechar">${X}</button></div>` +
    '<div class="modal-body form">' +
    '<div class="stack" style="gap:12px" data-para></div>' +
    '<div class="form-grid">' +
    '<div class="field"><label for="iw-conta">Enviar pela conta</label><select class="select" id="iw-conta"><option>DevBatista · +55 11 97070-2026</option></select></div>' +
    `<div class="field"><label for="iw-tpl">Template aprovado <span class="req">*</span></label><select class="select" id="iw-tpl" required>${Object.keys(TPL).map((k) => `<option value="${k}">${k} · ${TPL[k][0]}</option>`).join('')}</select></div>` +
    '</div>' +
    '<div class="form-grid" data-vars></div>' +
    '<div class="msg out"><span class="avatar sm" style="width:36px;height:36px;font-size:13px">R</span><div><div class="who"><b>Prévia</b> · como <span data-quem></span> recebe</div><div class="bubble" data-prev></div></div></div>' +
    '<span class="hint" data-hint></span>' +
    '</div>' +
    '<div class="modal-foot"><button class="btn" type="button" data-wa-fechar>Cancelar</button><button class="btn pri" type="submit">Enviar template</button></div>' +
    '</form>';
  document.body.appendChild(modal);

  const sel = modal.querySelector('#iw-tpl');
  const vars = modal.querySelector('[data-vars]');
  const prev = modal.querySelector('[data-prev]');
  let primeiro = '';

  const paint = () => {
    const vals = [...vars.querySelectorAll('input')].map((i) => i.value);
    prev.textContent = TPL[sel.value][1].replace(/\{\{(\d+)\}\}/g, (_, n) => vals[n - 1] || `{{${n}}}`);
  };
  const draw = () => {
    const [, , labels, vals] = TPL[sel.value];
    vars.innerHTML = labels.map((l, i) => `<div class="field"><label for="iw-v${i}">{{${i + 1}}} ${l} <span class="req">*</span></label><input class="input" id="iw-v${i}" required value="${esc(i === 0 ? primeiro : vals[i])}"></div>`).join('');
    paint();
  };
  sel.addEventListener('change', draw);
  vars.addEventListener('input', paint);

  const overlay = () => document.querySelector('.overlay');
  const fechar = () => { modal.classList.remove('open'); overlay().classList.remove('open'); };

  function abrir(b) {
    const d = b.dataset;
    const cadastro = d.cadastro || 'contato';
    primeiro = d.nome.split(' ')[0];
    const quem = `<b class="strong">${esc(d.nome)}</b>${d.org ? ' · ' + esc(d.org) : ''}`;
    modal.querySelector('[data-para]').innerHTML = d.numero
      ? `<div class="callout"><span>Para ${quem} · <span class="mono">${esc(d.numero)}</span></span></div>`
      : `<div class="callout warn" role="alert"><span><b class="strong">${esc(primeiro)} não tem WhatsApp cadastrado.</b> Informe o número para enviar o template.</span></div>` +
        `<div class="form-grid"><div class="field"><label for="iw-num">WhatsApp de ${esc(primeiro)} <span class="req">*</span></label><input class="input mono" id="iw-num" type="tel" required placeholder="(11) 98765-4321"></div>` +
        `<div class="field" style="justify-content:flex-end"><label class="check"><input type="checkbox" checked> Salvar no cadastro do ${cadastro}</label></div></div>`;
    modal.querySelector('[data-quem]').textContent = primeiro;
    modal.querySelector('[data-hint]').textContent = `A janela de 24h para mensagens livres abre quando ${primeiro} responder. A conversa fica ligada a este ${cadastro}.`;
    sel.value = TPL[d.tpl] ? d.tpl : 'retomada_contato';
    draw();
    document.querySelectorAll('.drawer.open').forEach((x) => x.classList.remove('open'));
    modal.classList.add('open');
    overlay().classList.add('open');
    setTimeout(() => (modal.querySelector('#iw-num') || sel).focus(), 30);
  }

  document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-wa-iniciar]');
    if (b) { e.preventDefault(); abrir(b); return; }
    if (e.target.closest('[data-wa-fechar]')) fechar();
  });
  modal.querySelector('form').addEventListener('submit', (e) => { e.preventDefault(); fechar(); });
})();
