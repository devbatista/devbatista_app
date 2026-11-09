require "rails_helper"

RSpec.describe SiteVisits::Stats do
  let(:now) { Time.zone.local(2026, 11, 9, 14, 0) }

  around { |example| travel_to(now) { example.run } }

  def stats(key = "7d", **filters) = described_class.new(described_class.period(key), filters)

  describe ".period" do
    it "monta cada período com o anterior de mesmo tamanho e o agrupamento" do
      today = described_class.period("hoje")
      expect([ today.range.begin, today.range.end, today.previous.begin, today.previous.end, today.bucket ])
        .to eq([ Time.zone.local(2026, 11, 9), now, Time.zone.local(2026, 11, 8), now - 1.day, :hour ])

      week = described_class.period("7d")
      expect([ week.range.begin, week.previous.begin, week.previous.end, week.bucket ])
        .to eq([ Time.zone.local(2026, 11, 3), Time.zone.local(2026, 10, 27), Time.zone.local(2026, 11, 2, 14, 0), :day ])

      last_month = described_class.period("mes_passado")
      expect([ last_month.range.begin.to_date, last_month.range.end.to_date, last_month.previous.begin.to_date, last_month.previous.end.to_date ])
        .to eq([ Date.new(2026, 10, 1), Date.new(2026, 10, 31), Date.new(2026, 9, 1), Date.new(2026, 9, 30) ])

      expect(described_class.period("12m")).to have_attributes(bucket: :month, label: "Últimos 12 meses")
      expect(described_class.period("12m").range.begin.to_date).to eq(Date.new(2025, 12, 1))
    end

    it "cai no padrão com chave desconhecida, e recusa no modo estrito" do
      expect(described_class.period("semana").key).to eq("7d")
      expect(described_class.period(nil).key).to eq("7d")
      expect { described_class.period("semana", strict: true) }.to raise_error(described_class::Invalid, /periodo desconhecido/)
    end

    it "aceita intervalo livre de até 400 dias, com o agrupamento pelo tamanho" do
      custom = described_class.period(de: "2026-10-01", ate: "2026-10-31")
      expect(custom).to have_attributes(key: "personalizado", label: "01/10/2026 a 31/10/2026", bucket: :day)
      expect(custom.previous.begin.to_date).to eq(Date.new(2026, 8, 31))
      expect(described_class.period(de: "2026-11-08").bucket).to eq(:hour)
      expect(described_class.period(de: "2026-01-01", ate: "2026-11-01").bucket).to eq(:month)

      expect { described_class.period(de: "2025-01-01", ate: "2026-11-01") }.to raise_error(described_class::Invalid, "Intervalo de até 400 dias.")
      expect { described_class.period(de: "2026-11-02", ate: "2026-11-01") }.to raise_error(described_class::Invalid, "de precisa ser antes de ate.")
      expect { described_class.period(de: "01/11/2026") }.to raise_error(described_class::Invalid, /AAAA-MM-DD/)
    end
  end

  describe "#summary" do
    before do
      create_site_visit(at: now - 2.hours, hash: "a", pages: %w[/ /sobre], duration: 120)
      create_site_visit(at: now - 1.hour, hash: "a", pages: %w[/contato], duration: 5)
      create_site_visit(at: now - 2.days, hash: "b", pages: %w[/ /solucoes /contato], duration: 300)
      create_site_visit(at: now - 9.days, hash: "c", pages: %w[/], duration: 30)
      create_site_visit(at: now - 30.days, hash: "velha")
    end

    it "calcula os seis indicadores, o anterior e a variação" do
      summary = stats.summary

      expect(summary[:indicadores]).to eq(visitantes: 2, visitas: 3, paginas_vistas: 6, paginas_por_visita: 2.0, taxa_rejeicao: 33.3, duracao_media: 142)
      expect(summary[:anterior]).to eq(visitantes: 1, visitas: 1, paginas_vistas: 1, paginas_por_visita: 1.0, taxa_rejeicao: 0, duracao_media: 30)
      expect(summary[:variacao]).to eq(visitantes: 100.0, visitas: 200.0, paginas_vistas: 500.0, paginas_por_visita: 100.0, taxa_rejeicao: 33.3, duracao_media: 373.3)
      expect(summary[:primeira_visita]).to eq((now - 30.days).to_date.iso8601)
      expect(summary[:periodo]).to include(chave: "7d", de: "2026-11-03", ate: "2026-11-09", agrupamento: "dia", anterior: { de: "2026-10-27", ate: "2026-11-02" })
    end

    it "monta a série com zero nos dias sem visita" do
      serie = stats.summary[:serie]

      expect(serie.map { |p| p[:inicio] }).to eq(("2026-11-03".."2026-11-09").to_a)
      expect(serie.map { |p| p[:visitas] }).to eq([ 0, 0, 0, 0, 1, 0, 2 ])
      expect(serie.last).to eq(inicio: "2026-11-09", visitantes: 1, visitas: 2, paginas_vistas: 3)
    end

    it "agrupa por hora em hoje e por dia no fuso do app, não em UTC" do
      late = create_site_visit(at: Time.zone.local(2026, 11, 8, 23, 30))
      expect(late.started_at.utc.to_date).to eq(Date.new(2026, 11, 9))

      expect(stats.summary[:serie].find { |p| p[:inicio] == "2026-11-08" }[:visitas]).to eq(1)
      hours = stats("hoje").summary[:serie]
      expect(hours.size).to eq(15)
      expect(hours.select { |p| p[:visitas].positive? }.map { |p| Time.zone.parse(p[:inicio]).hour }).to eq([ 12, 13 ])
    end

    it "aplica os filtros e recusa canal ou dispositivo desconhecido" do
      create_site_visit(at: now - 3.hours, channel: "search", referrer: "google.com", pages: %w[/faq], device: "mobile")

      expect(stats(canal: "search").summary[:indicadores][:visitas]).to eq(1)
      expect(stats(origem: "www.google.com").summary[:indicadores][:visitas]).to eq(1)
      expect(stats(origem: "direto").summary[:indicadores][:visitas]).to eq(3)
      expect(stats(pagina: "contato/").summary[:indicadores][:visitas]).to eq(2)
      expect(stats(pagina_entrada: "/").summary[:indicadores][:visitas]).to eq(2)
      expect(stats(dispositivo: "mobile").summary[:indicadores][:visitas]).to eq(1)
      expect(stats(canal: "direct", pagina: "/contato").summary[:indicadores][:visitas]).to eq(2)

      expect { stats(canal: "tv") }.to raise_error(described_class::Invalid, /canal desconhecido/)
      expect { stats(dispositivo: "relogio") }.to raise_error(described_class::Invalid, /dispositivo desconhecido/)
    end
  end

  describe "#by_dimension" do
    it "agrupa por canal com rótulo, percentual, rejeição e duração, do maior para o menor" do
      2.times { create_site_visit(at: now - 1.hour, channel: "search", referrer: "google.com", duration: 100) }
      create_site_visit(at: now - 1.hour, channel: "ai_assistant", referrer: "chatgpt.com", ai_assistant: "ChatGPT", duration: 4)

      result = stats.by_dimension("canal")
      expect(result[:total_visitas]).to eq(3)
      expect(result[:linhas]).to eq([
        { valor: "search", rotulo: "Busca", visitantes: 2, visitas: 2, paginas_vistas: 2, percentual: 66.7, taxa_rejeicao: 0, duracao_media: 100 },
        { valor: "ai_assistant", rotulo: "Assistentes de IA", visitantes: 1, visitas: 1, paginas_vistas: 1, percentual: 33.3, taxa_rejeicao: 100.0, duracao_media: 4 }
      ])
      expect(result[:outros]).to be_nil
      expect(stats.by_dimension("assistente_ia")[:linhas].map { |l| l[:rotulo] }).to eq([ "ChatGPT" ])
      expect(stats.by_dimension("origem")[:linhas].map { |l| l[:rotulo] }).to eq([ "google.com", "chatgpt.com" ])
    end

    it "na página, conta as visitas que passaram por ela e o tempo médio nela" do
      create_site_visit(at: now - 1.hour, pages: %w[/ /contato], duration: 60)
      create_site_visit(at: now - 1.hour, pages: %w[/contato], duration: 10)

      contato = stats.by_dimension("pagina")[:linhas].find { |l| l[:valor] == "/contato" }
      expect(contato).to include(visitas: 2, paginas_vistas: 2, percentual: 100.0, duracao_media: 20)
    end

    it "soma o que passa do limite em outros e ordena dia da semana e hora pelo calendário" do
      %w[/a /b /c].each_with_index { |path, i| (3 - i).times { create_site_visit(at: now - 1.hour, pages: [ path ]) } }
      create_site_visit(at: Time.zone.local(2026, 11, 8, 9, 0))

      result = stats.by_dimension("pagina_entrada", limit: 2)
      expect(result[:linhas].map { |l| l[:valor] }).to eq(%w[/a /b])
      expect(result[:outros]).to eq(grupos: 2, visitas: 2, paginas_vistas: 2)

      expect(stats.by_dimension("dia_da_semana")[:linhas].map { |l| l[:rotulo] }).to eq(%w[Domingo Segunda])
      expect(stats.by_dimension("hora")[:linhas].map { |l| l[:rotulo] }).to eq(%w[09h 13h])
    end

    it "esconde o rótulo de UTM com menos de 3 visitantes" do
      3.times { |i| create_site_visit(at: now - 1.hour, hash: "h#{i}", channel: "campaign", utm_campaign: "black-friday") }
      2.times { create_site_visit(at: now - 1.hour, hash: "ana", channel: "campaign", utm_campaign: "so-para-ana") }

      lines = stats.by_dimension("utm_campaign")[:linhas]
      expect(lines.first).to include(valor: "black-friday", visitantes: 3)
      expect(lines.second).to include(valor: nil, rotulo: "(oculto: menos de 3 visitantes)", visitantes: 1, visitas: 2, oculto: true)
    end

    it "recusa dimensão desconhecida" do
      expect { stats.by_dimension("cidade") }.to raise_error(described_class::Invalid, /dimensao desconhecida/)
    end
  end

  describe "#ai_hits" do
    before do
      create_ai_hit(at: now - 1.hour)
      create_ai_hit(at: now - 2.hours, path: "/solucoes")
      create_ai_hit(at: now - 1.hour, agent: "gptbot", name: "GPTBot", kind: "training", blocked: true)
      create_ai_hit(at: now - 1.hour, agent: "claude-user", name: "Claude-User", company: "Anthropic", verification: "declared")
      create_ai_hit(at: now - 1.hour, verification: "spoofed")
      create_ai_hit(at: now - 20.days)
      create_site_visit(at: now - 1.hour, channel: "ai_assistant", referrer: "chatgpt.com", ai_assistant: "ChatGPT")
    end

    it "agrupa por empresa, separa servidos e bloqueados, e deixa os falsos fora dos totais" do
      result = stats.ai_hits
      expect(result).to include(total: 4, servidos: 3, bloqueados: 1, falsos: 1)
      expect(result[:grupos]).to eq([
        { valor: "OpenAI", rotulo: "OpenAI", acessos: 3, servidos: 2, bloqueados: 1 },
        { valor: "Anthropic", rotulo: "Anthropic", acessos: 1, servidos: 1, bloqueados: 0 }
      ])
      expect(result[:por_tipo]).to eq([ { valor: "user", rotulo: "A pedido de alguém", acessos: 3 }, { valor: "training", rotulo: "Treino", acessos: 1 } ])
      expect(result[:visitas_de_assistentes_de_ia]).to eq(visitas: 1, por_assistente: { "ChatGPT" => 1 })
    end

    it "filtra e agrupa por tipo, página e dia, e mostra os falsos quando pedidos" do
      expect(stats.ai_hits(group: "tipo")[:grupos].map { |g| g[:rotulo] }).to eq([ "A pedido de alguém", "Treino" ])
      expect(stats.ai_hits(group: "pagina", filters: { empresa: "openai", tipo: "user" })[:grupos].map { |g| [ g[:valor], g[:acessos] ] })
        .to eq([ [ "/", 1 ], [ "/solucoes", 1 ] ])
      expect(stats.ai_hits(group: "dia")[:grupos].map { |g| g[:valor] }).to eq([ "2026-11-09" ])
      expect(stats.ai_hits(filters: { verificacao: "spoofed" })).to include(total: 1, falsos: nil)

      expect { stats.ai_hits(group: "pais") }.to raise_error(described_class::Invalid, /agrupar desconhecido/)
      expect { stats.ai_hits(filters: { tipo: "robo" }) }.to raise_error(described_class::Invalid, /tipo desconhecido/)
    end
  end
end
