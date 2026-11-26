# Pré-visualização em /rails/mailers (desenvolvimento).
class EbookMailerPreview < ActionMailer::Preview
  def download
    EbookMailer.download(to: "visitante@exemplo.com.br",
                         url: Rails.configuration.x.ebook.download_url || "https://www.devbatista.com/materiais/ebook.pdf")
  end
end
