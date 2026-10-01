# Requisitos funcionais — Comercial

[← Requisitos funcionais](README.md) · [Índice geral](../README.md)

6. **Leads.** Como comercial, quero registrar leads com origem e serviço de interesse.
   - Origem obrigatória entre: WhatsApp, Indicação, Site, Diagnóstico, Meta Ads, Google Ads, LinkedIn, Outbound, Outros.
   - Data de entrada preenchida automaticamente.
7. **Pipeline.** Como comercial, quero um quadro kanban com 7 etapas para arrastar os negócios entre elas.
   - Etapas: Novo Lead, Contato Realizado, Qualificado, Reunião, Proposta, Negociação, Fechado.
   - Perdido pode ser marcado em qualquer etapa aberta e exige motivo da perda.
   - Cada coluna mostra a quantidade e o valor somado.
   - Novo Lead, Contato Realizado e Qualificado mostram leads. De Reunião em diante o cartão é a oportunidade criada na conversão do lead.
8. **Converter lead.** Como comercial, quero converter um lead qualificado em empresa, contato e oportunidade sem redigitar dados.
   - A conversão preenche os campos a partir do lead e avisa se já existe empresa com o mesmo CNPJ.
9. **Oportunidades.** Como comercial, quero registrar valor estimado, probabilidade e previsão de fechamento.
   - Previsão ponderada = valor estimado × probabilidade, exibida no pipeline e nos relatórios.
10. **Propostas.** Como comercial, quero montar uma proposta com um ou mais serviços do catálogo.
    - O total é a soma dos itens; o preço de cada item vem do preço padrão e pode ser alterado.
    - Status: Rascunho, Enviada, Visualizada, Aprovada, Recusada, Expirada.
    - Proposta Enviada ou Visualizada vira Expirada ao fim da validade; o responsável é avisado 3 dias antes.
11. **Fechar negócio.** Como comercial, quero gerar contrato e serviços contratados a partir de uma proposta aprovada.
    - Cliente, serviços, valores e prazos vêm da proposta; a empresa passa a Ativo.
