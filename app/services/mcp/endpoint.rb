# Endpoint /mcp: o Admin DevBatista como servidor MCP, para virar conector do Claude
# (docs/specs/mcp-comercial/README.md).
#
# App Rack montado nas rotas. Cada requisição monta um transporte Streamable HTTP stateless
# que responde em JSON (sem sessão e sem SSE). O token do cabeçalho Authorization é conferido
# pelo TokenVerifier antes de qualquer leitura do corpo; sem token válido, 401 com o endereço
# da descoberta do OAuth (Mcp::Metadata) no WWW-Authenticate.
module Mcp
  class Endpoint
    TOOLS = [
      Tools::OpcoesComerciais,
      Tools::BuscarEmpresas,
      Tools::Pipeline,
      Tools::ProximosPassos,
      Tools::BuscarLeads,
      Tools::VerLead,
      Tools::VerConversaWhatsapp,
      Tools::BuscarOportunidades,
      Tools::VerOportunidade,
      Tools::BuscarPropostas,
      Tools::VerProposta,
      Tools::GerarPdfProposta,
      Tools::CriarLeads,
      Tools::AtualizarLead,
      Tools::MoverLead,
      Tools::ConverterLead,
      Tools::RegistrarInteracao,
      Tools::EnviarWhatsapp,
      Tools::MarcarPerdido,
      Tools::ConcluirPasso,
      Tools::CriarOportunidade,
      Tools::AtualizarOportunidade,
      Tools::MoverOportunidade,
      Tools::CriarProposta,
      Tools::RegistrarEvento,
      Tools::LerPendencias,
      Tools::ConcluirPendencia,
      Tools::VisitasResumo,
      Tools::VisitasPorDimensao,
      Tools::AcessosIa
    ].freeze

    INSTRUCTIONS = <<~TEXT.squish
      Admin DevBatista é o sistema de gestão da DevBatista, uma software house. Este servidor dá acesso ao
      Comercial: leads, pipeline, oportunidades, propostas e interações. Valores em reais, datas em AAAA-MM-DD,
      ids em UUID. O próximo passo de lead e oportunidade (proximo_passo_em) tem data e hora: AAAA-MM-DDTHH:MM,
      horário de Brasília (-03:00); só a data vale às 09:00. Antes de criar ou alterar registros, consulte
      opcoes_comerciais para usar as chaves aceitas. No começo de uma sessão comercial, chame proximos_passos;
      ao concluir uma ação, use concluir_passo.
      enviar_whatsapp manda mensagem real ao lead: chame antes com simular: true, mostre a prévia ao usuário e só
      envie o texto exato que ele aprovou no chat. Para ler o que o lead respondeu, use ver_conversa_whatsapp; para
      achar quem respondeu num dia, buscar_leads com com_resposta_whatsapp_desde.
      Se você é um agente do escritório (ops, sol, mia, leo, fin), em cada execução: ler_pendencias no começo,
      registrar_evento ao começar e ao terminar o trabalho (com precisa_aprovacao quando a ação exigir o aval do
      administrador) e concluir_pendencia para cada ordem atendida. Visitas do site devbatista.com (só leitura,
      números agregados): visitas_resumo, visitas_por_dimensao e acessos_ia. O visitante único é contado por dia,
      não há dados antes de primeira_visita, e acesso de robô ou agente de IA não é visita de pessoa.
    TEXT

    def self.call(env)
      # A auditoria marca o que veio do Claude (AuditLog#ip_address).
      Current.ip_address = "mcp:#{ActionDispatch::Request.new(env).remote_ip}"
      transport.call(env)
    end

    def self.transport
      MCP::Server::Transports::StreamableHTTPTransport.new(
        server,
        stateless: true,
        enable_json_response: true,
        serve_subscriptions_listen: false,
        token_verifier: TokenVerifier.new,
        required_scopes: Metadata::SCOPES,
        resource_metadata: Metadata.protected_resource,
        allowed_hosts: Rails.configuration.x.mcp.allowed_hosts
      )
    end

    def self.server
      MCP::Server.new(name: "admin-devbatista", title: "Admin DevBatista", version: "1.0.0",
                      instructions: INSTRUCTIONS, tools: TOOLS)
    end
  end
end
