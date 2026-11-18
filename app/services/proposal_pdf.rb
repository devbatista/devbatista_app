# PDF da proposta que vai para o cliente (RF 10). Prawn com a Montserrat da marca
# (vendor/fonts), sem depender de navegador na imagem.
#
#   pdf = ProposalPdf.new(proposal)
#   pdf.render    # => conteúdo binário do PDF
#   pdf.filename  # => "proposta-P-2026-001.pdf"
class ProposalPdf
  include BrandedPdf

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

  def header(pdf)
    band(pdf, label: "PROPOSTA COMERCIAL", code: @proposal.code, caption: "Emitida em #{date_br(@issued_on)}")
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
    pdf.text closing_line, size: 9, color: MUTED, inline_format: true
  end

  # E-mail do responsável e WhatsApp da empresa (Configurações), clicáveis no PDF.
  def closing_line
    email = escape(@proposal.user.email)
    line = "Para aprovar ou tirar dúvidas, envie um e-mail para <link href='mailto:#{email}'><color rgb='#{ACCENT}'>#{email}</color></link>"
    whatsapp = Setting[:company_whatsapp].presence
    line += " ou um WhatsApp para <link href='https://wa.me/55#{whatsapp}'><color rgb='#{ACCENT}'>#{unbreakable(Setting.format_phone(whatsapp))}</color></link>" if whatsapp
    "#{line}."
  end

  def footer_line
    cnpj = Setting[:company_cnpj].presence
    [ Setting[:company_legal_name], ("CNPJ #{CnpjValidator.format(cnpj)}" if cnpj),
      Setting[:company_site].to_s.delete_prefix("https://"), "Proposta #{@proposal.code}" ].compact_blank.join(" · ")
  end
end
