# PDF da fatura que vai para o cliente (docs/specs/faturas): cliente e emissor, itens (cópia das
# receitas), total e vencimento, e como pagar: Pix (QR Code e copia e cola) e dados bancários.
#
#   pdf = InvoicePdf.new(invoice)
#   pdf.render    # => conteúdo binário do PDF
#   pdf.filename  # => "fatura-FAT-2026-0001.pdf"
class InvoicePdf
  include BrandedPdf

  QR_SIZE = 132

  delegate :brl, :date_br, to: :helpers

  def initialize(invoice, view_url: nil)
    @invoice = invoice
    @view_url = view_url
  end

  def filename
    "fatura-#{@invoice.code.parameterize(preserve_case: true)}.pdf"
  end

  def render
    pdf = Prawn::Document.new(page_size: "A4", margin: [ 48, 48, 64, 48 ], info: {
      Title: "Fatura #{@invoice.code} — #{@invoice.company.trade_name}", Author: Setting[:company_name], Creator: "Admin DevBatista"
    })
    setup_fonts(pdf)
    band(pdf, label: "FATURA", code: @invoice.code, caption: caption)
    parties(pdf)
    summary(pdf)
    items(pdf)
    notes(pdf)
    payment(pdf)
    footer(pdf)
    pdf.render
  end

  private

  def caption
    @invoice.issued_on ? "Emitida em #{date_br(@invoice.issued_on)}" : "Rascunho, não enviar"
  end

  def parties(pdf)
    width = (pdf.bounds.width - 24) / 2
    top = pdf.cursor
    heights = [ [ 0, "PARA", recipient_lines ], [ width + 24, "DE", sender_lines ] ].map do |x, label, lines|
      pdf.bounding_box([ x, top ], width: width) do
        eyebrow(pdf, label)
        lines.each_with_index do |line, i|
          pdf.text clean(line), size: i.zero? ? 11 : 9, style: i.zero? ? :semibold : :normal, color: i.zero? ? INK : MUTED
        end
      end
      top - pdf.cursor
    end
    pdf.move_cursor_to top - heights.max
    pdf.move_down 20
    rule(pdf)
  end

  def recipient_lines
    company = @invoice.company
    [ company.legal_name, ("CNPJ #{CnpjValidator.format(company.cnpj)}" if company.cnpj.present?),
      address(company), @invoice.contact&.name, @invoice.recipient_email ].compact_blank
  end

  def address(company)
    [ company.street, [ company.city, company.state ].compact_blank.join("/") ].compact_blank.join(" · ").presence
  end

  def sender_lines
    cnpj = Setting[:company_cnpj].presence
    [ Setting[:company_legal_name], ("CNPJ #{CnpjValidator.format(cnpj)}" if cnpj),
      Setting[:company_site].to_s.delete_prefix("https://") ].compact_blank
  end

  # Valor e vencimento em destaque, logo abaixo das partes.
  def summary(pdf)
    pdf.move_down 20
    top = pdf.cursor
    width = pdf.bounds.width / 3
    status = @invoice.paid? ? "Paga em #{date_br(@invoice.paid_on)}" : (@invoice.cancelled? ? "Cancelada" : nil)
    [ [ "VALOR A PAGAR", brl(@invoice.total_cents) ], [ "VENCIMENTO", date_br(@invoice.due_on) ],
      [ "SITUAÇÃO", status || (@invoice.overdue? ? "Vencida" : "Em aberto") ] ].each_with_index do |(label, value), i|
      pdf.bounding_box([ width * i, top ], width: width - 12) do
        eyebrow(pdf, label)
        pdf.text value, size: i.zero? ? 18 : 13, style: :bold, color: i == 2 && (@invoice.overdue? || @invoice.cancelled?) ? "B91C1C" : INK
      end
    end
    pdf.move_cursor_to top - 52
  end

  def items(pdf)
    section(pdf, "Itens")
    rows = [ [ "Descrição", "Competência", "Valor" ] ]
    @invoice.items.each { |item| rows << [ escape(item.description), item.competence_label, brl(item.amount_cents) ] }
    pdf.table(rows, header: true, width: pdf.bounds.width, column_widths: { 1 => 110, 2 => 100 },
                    cell_style: { size: 9, padding: [ 8, 10 ], borders: [ :bottom ], border_color: RULE, border_width: 0.75,
                                  inline_format: true, text_color: INK }) do |t|
      t.row(0).font_style = :semibold
      t.row(0).size = 8
      t.row(0).text_color = MUTED
      t.row(0).background_color = ZEBRA
      t.columns(2).align = :right
    end
    pdf.move_down 10
    pdf.bounding_box([ pdf.bounds.width - 240, pdf.cursor ], width: 240) do
      kv(pdf, "Total", brl(@invoice.total_cents), size: 12, style: :bold, color: INK)
    end
  end

  def notes(pdf)
    return if @invoice.client_notes.blank?

    section(pdf, "Observações", keep: 50)
    pdf.text clean(@invoice.client_notes), size: 9, leading: 3
  end

  # Pix (QR à esquerda, copia e cola à direita) e dados bancários. Paga ou cancelada: só o aviso.
  def payment(pdf)
    section(pdf, "Como pagar", keep: QR_SIZE + 60)
    unless @invoice.issued? || @invoice.draft?
      pdf.text(@invoice.paid? ? "Fatura paga em #{date_br(@invoice.paid_on)}. Obrigado!" : "Fatura cancelada: não pague este documento.", size: 10, style: :semibold)
      return
    end

    pix = PixPayload.new(amount_cents: @invoice.total_cents, txid: @invoice.txid)
    if pix.available?
      top = pdf.cursor
      draw_qr(pdf, pix, top)
      pdf.bounding_box([ QR_SIZE + 20, top ], width: pdf.bounds.width - QR_SIZE - 20) do
        pdf.text "Pix", size: 11, style: :bold
        pdf.text "Abra o app do banco, escolha pagar com Pix e leia o QR Code ou cole o código abaixo.", size: 9, color: MUTED
        pdf.move_down 6
        pdf.text "Chave: #{pix.key_label}", size: 9, style: :semibold
        pdf.move_down 6
        pdf.text "Pix copia e cola", size: 7.5, style: :semibold, color: ACCENT
        pdf.text pix.to_s, size: 7, color: INK, leading: 1
      end
      pdf.move_cursor_to [ top - QR_SIZE, pdf.cursor ].min
    end

    bank = Setting[:bank_details].to_s.strip
    if bank.present?
      pdf.move_down 16
      pdf.text "Transferência", size: 11, style: :bold
      pdf.text clean(bank), size: 9, color: MUTED, leading: 2
    end
    line = closing_line
    return unless line

    pdf.move_down 16
    pdf.text line, size: 9, color: MUTED, inline_format: true
  end

  def draw_qr(pdf, pix, top)
    modules = pix.qr_modules
    cell = QR_SIZE.to_f / modules.size
    pdf.fill_color INK
    modules.each_with_index do |row, y|
      row.each_with_index do |dark, x|
        pdf.fill_rectangle [ x * cell, top - (y * cell) ], cell + 0.05, cell + 0.05 if dark
      end
    end
    pdf.fill_color INK
  end

  def closing_line
    parts = []
    parts << "Fatura on-line: <link href='#{@view_url}'><color rgb='#{ACCENT}'>#{escape(@view_url)}</color></link>." if @view_url
    whatsapp = Setting[:company_whatsapp].presence
    parts << "Dúvidas pelo WhatsApp <link href='https://wa.me/55#{whatsapp}'><color rgb='#{ACCENT}'>#{unbreakable(Setting.format_phone(whatsapp))}</color></link>." if whatsapp
    parts.join(" ").presence
  end

  def footer_line
    cnpj = Setting[:company_cnpj].presence
    [ Setting[:company_legal_name], ("CNPJ #{CnpjValidator.format(cnpj)}" if cnpj),
      Setting[:company_site].to_s.delete_prefix("https://"), "Fatura #{@invoice.code}" ].compact_blank.join(" · ")
  end
end
