require "net/http"

# Cotação PTAX de venda do Banco Central (API Olinda, sem autenticação).
# Busca o último boletim de fechamento até a data pedida, olhando 7 dias para trás para
# cobrir fins de semana e feriados. Em caso de falha devolve nil; quem chama decide o fallback.
#
#   BcbPtax.fetch("USD", Date.new(2026, 9, 17)) # => { quoted_on: 2026-09-17, rate: 5.6201 }
class BcbPtax
  ENDPOINT = "https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata/" \
             "CotacaoMoedaPeriodo(moeda=@moeda,dataInicial=@dataInicial,dataFinalCotacao=@dataFinalCotacao)".freeze
  TIMEOUT = 5

  class_attribute :enabled, default: !Rails.env.test?

  def self.fetch(currency, date)
    return unless enabled

    uri = URI(ENDPOINT)
    uri.query = URI.encode_www_form("@moeda" => "'#{currency}'", "@dataInicial" => "'#{(date - 7).strftime('%m-%d-%Y')}'",
                                    "@dataFinalCotacao" => "'#{date.strftime('%m-%d-%Y')}'", "$format" => "json")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      http.get(uri.request_uri)
    end
    return log_failure(currency, date, "HTTP #{response.code}") unless response.is_a?(Net::HTTPSuccess)

    quotes = JSON.parse(response.body).fetch("value", [])
    quote = quotes.select { |q| q["tipoBoletim"] == "Fechamento" }.max_by { |q| q["dataHoraCotacao"] } || quotes.max_by { |q| q["dataHoraCotacao"] }
    return log_failure(currency, date, "sem cotação no período") unless quote

    { quoted_on: Date.parse(quote["dataHoraCotacao"]), rate: BigDecimal(quote["cotacaoVenda"].to_s) }
  rescue StandardError => e
    log_failure(currency, date, e.message)
  end

  def self.log_failure(currency, date, reason)
    Rails.logger.warn("[BcbPtax] #{currency} #{date}: #{reason}")
    nil
  end
end
