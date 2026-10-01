# Gera CNPJs válidos para os testes.
module CnpjHelper
  def self.generate(seed)
    base = format("%08d0001", seed).chars.map(&:to_i)
    d1 = CnpjValidator.check_digit(base, CnpjValidator::WEIGHTS_1)
    d2 = CnpjValidator.check_digit(base + [ d1 ], CnpjValidator::WEIGHTS_2)
    (base + [ d1, d2 ]).join
  end
end
