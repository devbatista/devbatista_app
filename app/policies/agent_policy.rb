# Escritório de agentes de IA (docs/specs/escritorio-agentes): quem lê a área vê a planta, o painel
# e os eventos. Na v1, só o administrador tem a área.
class AgentPolicy < ApplicationPolicy
  area "agentes"
end
