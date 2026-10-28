module Whatsapp
  # Telefone da conversa (wa_id, sempre com o código do país) e telefone do cadastro no CRM (como a
  # pessoa digitou: "(11) 99102-3344", "+55 11 9102-3344"…). O mesmo celular do Brasil pode aparecer
  # com e sem o nono dígito depois do DDD: a Meta manda um ou outro conforme a conta, e o cadastro
  # pode ter qualquer um dos dois.
  module Phone
    module_function

    # Formas em que o número da conversa pode estar gravado no CRM, só os dígitos: com e sem o 55,
    # com e sem o 0 do DDD e, nos celulares, com e sem o nono dígito. Fora do Brasil, o próprio número.
    def stored_forms(wa_id)
      digits = wa_id.to_s.gsub(/\D/, "")
      return [] if digits.empty?

      ddd, number = brazilian_parts(digits, international: true)
      return [ digits ] unless ddd

      numbers(number).flat_map { |n| [ "#{ddd}#{n}", "55#{ddd}#{n}", "0#{ddd}#{n}" ] }
    end

    # Números da conversa (wa_id) que correspondem a um telefone do cadastro. Sem o código do país,
    # 10 ou 11 dígitos são do Brasil.
    def wa_ids(value)
      digits = value.to_s.gsub(/\D/, "")
      return [] if digits.length < 8

      ddd, number = brazilian_parts(digits, international: value.to_s.strip.start_with?("+"))
      return [ digits ] unless ddd

      numbers(number).map { |n| "55#{ddd}#{n}" }
    end

    # "(11) 99102-3344" para gravar no cadastro; fora do Brasil, "+" e os dígitos.
    def national_label(wa_id)
      digits = wa_id.to_s.gsub(/\D/, "")
      return if digits.empty?

      ddd, number = brazilian_parts(digits, international: true)
      ddd ? "(#{ddd}) #{number[0..-5]}-#{number[-4..]}" : "+#{digits}"
    end

    # DDD e número de um telefone do Brasil. Com international, o número precisa vir com o 55.
    def brazilian_parts(digits, international:)
      national =
        if digits.start_with?("55") && digits.length.in?([ 12, 13 ])
          digits[2..]
        elsif !international
          digits = digits.delete_prefix("0") if digits.length.in?([ 11, 12 ])
          digits if digits.length.in?([ 10, 11 ])
        end
      [ national[0, 2], national[2..] ] if national
    end

    # O número e a outra forma do celular: sem o 9 (9 dígitos começando por 9) ou com o 9
    # (8 dígitos de celular, começando de 6 a 9). Fixo fica como está.
    def numbers(number)
      if number.length == 9 && number.start_with?("9")
        [ number, number[1..] ]
      elsif number.length == 8 && number[0].in?(%w[6 7 8 9])
        [ number, "9#{number}" ]
      else
        [ number ]
      end
    end
  end
end
