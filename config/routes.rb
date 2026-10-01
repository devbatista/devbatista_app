Rails.application.routes.draw do
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development? && defined?(LetterOpenerWeb)

  devise_for :users, path: "", path_names: { sign_in: "entrar", sign_out: "sair", password: "senha", new: "nova", edit: "editar" }

  root "dashboard#show"

  # URLs em português: /administracao/usuarios/novo, /administracao/usuarios/1/editar.
  scope path_names: { new: "novo", edit: "editar" } do
    namespace :admin, path: "administracao" do
      resources :users, path: "usuarios", except: %i[show destroy] do
        patch :toggle_active, on: :member, path: "ativacao"
      end
      resource :permissions, path: "permissoes", only: %i[show update]
      resources :audit_logs, path: "logs", only: :index
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
