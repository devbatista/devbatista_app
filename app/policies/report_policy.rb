# Relatórios, indicadores e rentabilidade (RF 38, 39 e 40). Todos os perfis leem a área;
# dentro dela, cada relatório e cada indicador ainda respeita a área de origem dos dados.
class ReportPolicy < ApplicationPolicy
  area "relatorios"

  # Rentabilidade expõe receita e custo por cliente: só Administrador e Financeiro.
  def profitability?
    index? && user.sees_financials?
  end
end
