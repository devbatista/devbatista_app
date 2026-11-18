# Pix "copia e cola" estático (BR Code do Banco Central, formato EMV-MPM) para a fatura: chave,
# recebedor, cidade, valor e identificador da transação, fechado pelo CRC16-CCITT. O mesmo texto
# vira o QR Code (PDF e link público).
#
#   pix = PixPayload.new(amount_cents: 380_000, txid: "FAT20260001")
#   pix.available?  # => false sem chave Pix nas Configurações
#   pix.to_s        # => "00020126...6304ABCD"
#   pix.qr_svg      # => <svg ...>
class PixPayload
  GUI = "br.gov.bcb.pix".freeze

  def self.configured?
    Setting[:pix_key].to_s.strip.present?
  end

  def initialize(amount_cents:, txid:, key: Setting[:pix_key], name: nil, city: Setting[:pix_receiver_city])
    @amount_cents = amount_cents.to_i
    @txid = txid.to_s.gsub(/[^A-Za-z0-9]/, "").first(25).presence || "***"
    @key = PixKey.normalize(nil, key)
    @name = ascii(name.presence || Setting[:pix_receiver_name].presence || Setting[:company_legal_name]).first(25)
    @city = ascii(city.presence || "SAO PAULO").first(15)
  end

  def available?
    @key.present?
  end

  def key
    @key
  end

  # Chave para mostrar ao cliente: CNPJ pontuado, celular com DDD.
  def key_label
    PixKey.format(@key)
  end

  def to_s
    return "" unless available?

    payload = [
      field("00", "01"),
      field("26", field("00", GUI) + field("01", @key)),
      field("52", "0000"),
      field("53", "986"),
      (field("54", format("%.2f", @amount_cents / 100.0)) if @amount_cents.positive?),
      field("58", "BR"),
      field("59", @name),
      field("60", @city),
      field("62", field("05", @txid))
    ].compact.join + "6304"
    payload + crc16(payload)
  end

  # Módulos do QR Code (true = escuro), para o PDF desenhar.
  def qr_modules
    qr.modules
  end

  def qr_svg(size: 220)
    qr.as_svg(module_size: 4, standalone: true, use_path: true, viewbox: true, svg_attributes: { width: size, height: size, role: "img", "aria-label": "QR Code do Pix" })
  end

  private

  def qr
    @qr ||= RQRCode::QRCode.new(to_s, level: :m)
  end

  def field(id, value)
    "#{id}#{format('%02d', value.bytesize)}#{value}"
  end

  def ascii(text)
    I18n.transliterate(text.to_s).upcase.gsub(/[^A-Z0-9 .\-]/, "").squish
  end

  def crc16(payload)
    crc = 0xFFFF
    payload.each_byte do |byte|
      crc ^= byte << 8
      8.times { crc = (crc & 0x8000).zero? ? (crc << 1) : ((crc << 1) ^ 0x1021) }
      crc &= 0xFFFF
    end
    format("%04X", crc)
  end
end
