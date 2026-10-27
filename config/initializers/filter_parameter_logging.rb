# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
# code_verifier é o segredo do PKCE no /oauth/token do MCP; o code o Doorkeeper já filtra.
# entry é o corpo do webhook do WhatsApp (mensagens e telefones); só o nome exato, para não pegar time_entry.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc, :code_verifier, /\Aentry\z/
]
