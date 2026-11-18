# Identidade visual dos PDFs que vão para o cliente (proposta e fatura): Prawn com a Montserrat
# da marca (vendor/fonts), faixa escura no topo com o logo, rodapé com a razão social e as
# páginas, e os títulos de seção. A classe define footer_line.
module BrandedPdf
  FONT_DIR = Rails.root.join("vendor/fonts/montserrat")
  LOGO = Rails.root.join("app/assets/images/logo-devbatista-branco.png")

  # Cores do design system adaptadas ao papel (fundo branco).
  INK = "0F172A".freeze
  MUTED = "64748B".freeze
  RULE = "E2E8F0".freeze
  ZEBRA = "F8FAFC".freeze
  ACCENT = "0891B2".freeze
  BAND = "0B1120".freeze

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

  # Faixa escura no topo da primeira página, com o logo branco, o tipo e o número do documento.
  def band(pdf, label:, code:, caption:)
    height = 104
    pdf.canvas do
      top = pdf.bounds.top
      pdf.fill_color BAND
      pdf.fill_rectangle [ 0, top ], pdf.bounds.width, height
      pdf.image LOGO.to_s, at: [ 48, top - 36 ], width: 128 if LOGO.exist?
      pdf.bounding_box([ pdf.bounds.width - 48 - 240, top - 30 ], width: 240) do
        pdf.fill_color "67E8F9"
        pdf.text label, size: 8, style: :semibold, character_spacing: 1.5, align: :right
        pdf.fill_color "FFFFFF"
        pdf.text code, size: 16, style: :bold, align: :right
        pdf.fill_color "94A3B8"
        pdf.text caption, size: 8, align: :right
      end
    end
    pdf.fill_color INK
    pdf.move_down height - 48 + 20
  end

  def footer(pdf)
    pdf.repeat(:all) do
      pdf.bounding_box([ 0, -20 ], width: pdf.bounds.width, height: 20) do
        pdf.stroke_color RULE
        pdf.stroke_horizontal_rule
        pdf.move_down 8
        pdf.text footer_line, size: 7.5, color: MUTED
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

  # O Prawn quebra linha em espaço e no "-": troca por espaço inquebrável e pelo hífen U+2010
  # (a Montserrat não tem o U+2011), para o telefone não se dividir entre duas linhas.
  def unbreakable(text)
    text.tr(" -", " ‐")
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
