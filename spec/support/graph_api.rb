# Substitui o Net::HTTP nas chamadas à Graph API, sem WebMock (como no financeiro_spec).
#
#   requests = stub_graph(graph_response(200, { "messages" => [ { "id" => "wamid.1" } ] }))
#   ... chama o cliente ...
#   requests.first.path  # pedido feito, para conferir caminho, corpo e cabeçalhos
#
# Cada chamada consome a próxima resposta, na ordem; uma chamada a mais falha o teste.
module GraphApiHelpers
  def stub_graph(*responses)
    requests = []
    http = instance_double(Net::HTTP)
    allow(http).to receive(:request) do |req, &block|
      requests << req
      response = responses.shift || raise("chamada inesperada à Graph API: #{req.method} #{req.path}")
      block&.call(response)
      response
    end
    allow(Net::HTTP).to receive(:start) { |*_args, **_options, &block| block.call(http) }
    requests
  end

  def graph_response(status, body = {})
    text = body.is_a?(String) ? body : JSON.generate(body)
    response = Net::HTTPResponse::CODE_TO_OBJ.fetch(status.to_s).new("1.1", status.to_s, "")
    allow(response).to receive(:body).and_return(text)
    allow(response).to receive(:read_body).and_yield(text)
    response
  end

  def graph_error(status, code, message = "(##{code}) erro", details: nil, transient: nil)
    graph_response(status, { "error" => { "message" => message, "type" => "OAuthException", "code" => code,
                                          "error_data" => { "messaging_product" => "whatsapp", "details" => details },
                                          "fbtrace_id" => "AbCdEf123", "is_transient" => transient }.compact })
  end

  def json_body(request)
    JSON.parse(request.body)
  end
end

RSpec.configure { |config| config.include GraphApiHelpers }
