require "rails_helper"

RSpec.describe CsvExport do
  it "gera CSV com BOM, ponto e vírgula e vírgula decimal, protegendo fórmulas" do
    csv = described_class.generate([ "Cliente", "Valor" ], [ [ "ACME; Ltda", described_class.money(123_456) ], [ "=SOMA(A1)", -12.5 ] ])
    expect(csv).to eq "﻿Cliente;Valor\r\n\"ACME; Ltda\";1234,56\r\n'=SOMA(A1);-12,50\r\n"
  end
end
