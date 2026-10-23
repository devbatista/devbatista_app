module Mcp
  module Tools
    # Os links abrem o PDF gerado na hora (Commercial::ProposalsController#pdf), com login no sistema.
    class GerarPdfProposta < Base
      tool_name "gerar_pdf_proposta"
      title "PDF da proposta"
      description <<~TEXT.squish
        Devolve os links do PDF de uma proposta, gerado na hora com os dados atuais: um para abrir no navegador e
        outro para baixar. Os links pedem login no Admin DevBatista. Não envia nada ao cliente.
      TEXT
      read_only
      input_schema(properties: { id: { type: "string", description: "Id da proposta" } }, required: [ "id" ], additionalProperties: false)

      def execute(id:)
        proposal = authorize(Proposal.find(id))

        { codigo: proposal.code, titulo: proposal.title, arquivo: ProposalPdf.new(proposal).filename,
          abrir: link(:pdf_proposal, proposal), baixar: link(:pdf_proposal, proposal, baixar: 1) }
      end
    end
  end
end
