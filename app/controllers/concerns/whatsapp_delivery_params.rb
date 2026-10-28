# Parâmetros do envio de template e dos arquivos, no campo de envio da conversa e no "Iniciar conversa".
module WhatsappDeliveryParams
  private

  def template_values
    params[:values].respond_to?(:permit) ? params[:values].permit(body: [], header: [], buttons: {}).to_h : {}
  end

  def upload(name)
    file = params[name]
    file if file.respond_to?(:content_type)
  end
end
