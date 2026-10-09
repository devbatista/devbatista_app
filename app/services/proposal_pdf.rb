# PDF da proposta que vai para o cliente (RF 10). Prawn com a Montserrat da marca
# (vendor/fonts), sem depender de navegador na imagem.
#
#   pdf = ProposalPdf.new(proposal)
#   pdf.render    # => conteúdo binário do PDF
#   pdf.filename  # => "proposta-P-2026-001.pdf"
class ProposalPdf
  FONT_DIR = Rails.root.join("vendor/fonts/montserrat")
  LOGO = Rails.root.join("app/assets/images/logo-devbatista-branco.png")

  # Cores do design system adaptadas ao papel (fundo branco).
  INK = "0F172A".freeze
  MUTED = "64748B".freeze
  RULE = "E2E8F0".freeze
  ZEBRA = "F8FAFC".freeze
  ACCENT = "0891B2".freeze
  BAND = "0B1120".freeze

  PERIOD = { "monthly" => "por mês", "quarterly" => "por trimestre", "semiannual" => "por semestre",
             "annual" => "por ano", "one_off" => "pagamento único" }.freeze
  SUFFIX = { "monthly" => "/mês", "quarterly" => "/trimestre", "semiannual" => "/semestre", "annual" => "/ano" }.freeze

  delegate :brl, :date_br, to: :helpers

  def initialize(proposal, issued_on: Date.current)
    @proposal = proposal
    @issued_on = issued_on
  end

  def filename
    "proposta-#{@proposal.code.delete('#')}.pdf"
  end

  def render
    pdf = Prawn::Document.new(page_size: "A4", margin: [ 48, 48, 64, 48 ], info: {
      Title: "Proposta #{@proposal.code} — #{@proposal.title}", Author: Setting[:company_name], Creator: "Admin DevBatista"
    })
    setup_fonts(pdf)
    header(pdf)
    parties(pdf)
    title(pdf)
    description(pdf)
    items(pdf)
    conditions(pdf)
    closing(pdf)
    footer(pdf)
    pdf.render
  end

  private

  def helpers = ApplicationController.helpers

  def setup_fonts(pdf)
    pdf.font_families.update("Montserrat" => {
      normal: FONT_DIR.join("Montserrat-Regular.ttf").to_s,
      semibold: FONT_DIR.join("Montserrat-SemiBold.ttf").to_s,
      bold: FONT_DIR.join("Montserrat-Bold.ttf").to_s
    })
    pdf.font "Montserrat", size: 10
    pdf.default_leading 2
    pdf.fill_color INK
  end

  # Faixa escura no topo da primeira página, com o logo branco e o número da proposta.
  def header(pdf)
    band = 104
    pdf.canvas do
      top = pdf.bounds.top
      pdf.fill_color BAND
      pdf.fill_rectangle [ 0, top ], pdf.bounds.width, band
      pdf.image LOGO.to_s, at: [ 48, top - 36 ], width: 128 if LOGO.exist?
      pdf.bounding_box([ pdf.bounds.width - 48 - 240, top - 30 ], width: 240) do
        pdf.fill_color "67E8F9"
        pdf.text "PROPOSTA COMERCIAL", size: 8, style: :semibold, character_spacing: 1.5, align: :right
        pdf.fill_color "FFFFFF"
        pdf.text @proposal.code, size: 16, style: :bold, align: :right
        pdf.fill_color "94A3B8"
        pdf.text "Emitida em #{date_br(@issued_on)}", size: 8, align: :right
      end
    end
    pdf.fill_color INK
    pdf.move_down band - 48 + 20
  end

  def parties(pdf)
    width = (pdf.bounds.width - 24) / 2
    top = pdf.cursor
    heights = [ [ 0, "PARA", recipient_lines ], [ width + 24, "DE", sender_lines ] ].map do |x, label, lines|
      pdf.bounding_box([ x, top ], width: width) do
        eyebrow(pdf, label)
        lines.each_with_index do |line, i|
          pdf.text line, size: i.zero? ? 11 : 9, style: i.zero? ? :semibold : :normal, color: i.zero? ? INK : MUTED
        end
      end
      top - pdf.cursor
    end
    pdf.move_cursor_to top - heights.max
    pdf.move_down 20
    rule(pdf)
  end

  def recipient_lines
    p = @proposal
    if p.company
      [ p.company.trade_name, (p.company.legal_name if p.company.legal_name != p.company.trade_name),
        p.contact&.name, p.contact&.email ]
    else
      lead = p.lead
      [ lead.display_name, (lead.name if lead.company_name.present?), lead.email ]
    end.compact_blank
  end

  def sender_lines
    [ Setting[:company_name], @proposal.user.name, @proposal.user.email, Setting[:company_site].to_s.delete_prefix("https://") ].compact_blank
  end

  def title(pdf)
    pdf.move_down 20
    pdf.text clean(@proposal.title), size: 20, style: :bold, leading: 0
    pdf.move_down 6
    pdf.text "Válida até #{date_br(@proposal.valid_until)}", size: 9, style: :semibold, color: ACCENT
  end

  def description(pdf)
    return if @proposal.description.blank?

    section(pdf, "Descrição e escopo")
    pdf.text clean(@proposal.description), size: 10, leading: 3
  end

  def items(pdf)
    section(pdf, "Serviços")
    rows = [ [ "Serviço", "Recorrência", "Valor" ] ]
    @proposal.items.each do |item|
      name = "<b>#{escape(item.service.name)}</b>"
      name += "\n<font size='8'><color rgb='#{MUTED}'>#{escape(item.description)}</color></font>" if item.description.present?
      rows << [ name, item.recurrence_label, "#{brl(item.price_cents)}#{SUFFIX[item.recurrence]}" ]
    end

    pdf.table(rows, header: true, width: pdf.bounds.width, column_widths: { 1 => 92, 2 => 112 },
                    cell_style: { size: 9, padding: [ 8, 10 ], borders: [ :bottom ], border_color: RULE, border_width: 0.75,
                                  inline_format: true, text_color: INK }) do |t|
      t.row(0).font_style = :semibold
      t.row(0).size = 8
      t.row(0).text_color = MUTED
      t.row(0).background_color = ZEBRA
      t.columns(2).align = :right
    end

    totals(pdf)
  end

  # Subtotal por recorrência e total (soma dos itens, como na tela da proposta).
  def totals(pdf)
    groups = @proposal.items.group_by(&:recurrence)
    lines = ProposalItem::RECURRENCE_LABELS.keys.filter_map do |recurrence|
      next unless groups[recurrence]

      [ "#{ProposalItem::RECURRENCE_LABELS[recurrence]} · #{PERIOD[recurrence]}", brl(groups[recurrence].sum(&:price_cents)) ]
    end
    lines = [] if lines.size == 1

    pdf.move_down 10
    box = 240
    pdf.bounding_box([ pdf.bounds.width - box, pdf.cursor ], width: box) do
      lines.each do |label, value|
        kv(pdf, label, value, size: 9, color: MUTED)
      end
      pdf.move_down 4 if lines.any?
      kv(pdf, "Total da proposta", brl(@proposal.total_cents), size: 12, style: :bold, color: INK)
    end
  end

  def conditions(pdf)
    rows = [ [ "Forma de pagamento", @proposal.payment_terms ], [ "Prazo", @proposal.delivery_terms ],
             [ "Validade", "Até #{date_br(@proposal.valid_until)}" ] ].select { |_, value| value.present? }
    section(pdf, "Condições")
    pdf.table(rows, width: pdf.bounds.width, column_widths: { 0 => 150 },
                    cell_style: { size: 9, padding: [ 7, 0 ], borders: [ :bottom ], border_color: RULE, border_width: 0.75 }) do |t|
      t.columns(0).text_color = MUTED
      t.columns(1).font_style = :semibold
    end

    return if @proposal.notes.blank?

    section(pdf, "Observações", keep: 50)
    pdf.text clean(@proposal.notes), size: 9, leading: 3
  end

  def closing(pdf)
    pdf.move_down 28
    pdf.text "Para aprovar ou tirar dúvidas, responda o e-mail desta proposta ou fale com " \
             "#{@proposal.user.name} (#{@proposal.user.email}).", size: 9, color: MUTED
  end

  def footer(pdf)
    pdf.repeat(:all) do
      pdf.bounding_box([ 0, -20 ], width: pdf.bounds.width, height: 20) do
        pdf.stroke_color RULE
        pdf.stroke_horizontal_rule
        pdf.move_down 8
        pdf.text [ Setting[:company_legal_name], Setting[:company_site].to_s.delete_prefix("https://"), "Proposta #{@proposal.code}" ].compact_blank.join(" · "),
                 size: 7.5, color: MUTED
      end
    end
    pdf.number_pages "Página <page> de <total>", at: [ pdf.bounds.right - 120, -28 ], width: 120, align: :right, size: 7.5, color: MUTED
  end

  # Título de seção; `keep` evita deixá-lo sozinho no pé da página.
  def section(pdf, label, keep: 90)
    pdf.move_down 22
    pdf.start_new_page if pdf.cursor < keep
    eyebrow(pdf, label.upcase)
  end

  def eyebrow(pdf, label)
    pdf.text label, size: 7.5, style: :semibold, character_spacing: 1.2, color: ACCENT
    pdf.move_down 6
  end

  def kv(pdf, label, value, size:, color:, style: :normal)
    top = pdf.cursor
    pdf.text_box label, at: [ 0, top ], width: pdf.bounds.width - 110, size: size, style: style, color: color
    pdf.text_box value, at: [ pdf.bounds.width - 110, top ], width: 110, size: size, style: style == :normal ? :semibold : style, color: INK, align: :right
    pdf.move_down size + 8
  end

  def rule(pdf)
    pdf.stroke_color RULE
    pdf.line_width 0.75
    pdf.stroke_horizontal_rule
  end

  # Texto digitado entra em células com inline_format: escapa a marcação do Prawn.
  def escape(text)
    clean(text).gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
  end

  # Emojis não existem na Montserrat e sairiam como quadrados.
  def clean(text)
    text.to_s.gsub(/[\p{Extended_Pictographic}\u{FE0F}\u{200D}]/, "").squeeze(" ").strip
  end
end
