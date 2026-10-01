RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include ActiveJob::TestHelper

  # O Rails 8 carrega as rotas sob demanda; o Devise precisa delas para o sign_in nos testes.
  config.before(:suite) { Rails.application.reload_routes_unless_loaded }
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
