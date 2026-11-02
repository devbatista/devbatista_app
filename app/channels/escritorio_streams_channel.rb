# Turbo Stream do escritório de agentes (planta e painel). Além do nome assinado do stream
# (Turbo::StreamsChannel), exige que a pessoa possa ver a área Agentes IA.
#
#   <%= turbo_stream_from :escritorio, channel: EscritorioStreamsChannel %>
class EscritorioStreamsChannel < Turbo::StreamsChannel
  def subscribed
    return reject unless AgentPolicy.new(current_user, Agent).index?

    super
  end
end
