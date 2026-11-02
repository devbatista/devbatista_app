# Eventos registrados pelos agentes: quem lê a área vê a linha do tempo e a listagem; aprovar ou
# rejeitar um pedido exige escrita. Registrar eventos (create?) é das tools do MCP, com a mesma regra.
class AgentEventPolicy < ApplicationPolicy
  area "agentes"

  def decide?
    update?
  end
end
