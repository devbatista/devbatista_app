Rails.application.routes.draw do
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development? && defined?(LetterOpenerWeb)

  devise_for :users, path: "", path_names: { sign_in: "entrar", sign_out: "sair", password: "senha", new: "nova", edit: "editar" }

  root "dashboard#show"

  # URLs em português: /empresas/novo, /empresas/1/editar.
  scope path_names: { new: "novo", edit: "editar" } do
    resources :companies, path: "empresas", except: :destroy
    resources :contacts, path: "contatos", except: :show do
      patch :make_primary, on: :member, path: "principal"
    end
    resources :contracts, path: "contratos", except: :destroy
    resources :customer_services, path: "servicos-contratados", except: %i[show destroy]
    resources :documents, path: "documentos", only: %i[index new create show destroy]

    resources :notifications, path: "notificacoes", only: %i[index update] do
      patch :read_all, on: :collection, path: "marcar-todas"
      patch :preferences, on: :collection, path: "preferencias"
    end
    get "busca", to: "search#index", as: :search

    namespace :admin, path: "administracao" do
      resources :users, path: "usuarios", except: %i[show destroy] do
        patch :toggle_active, on: :member, path: "ativacao"
      end
      resource :permissions, path: "permissoes", only: %i[show update]
      resources :audit_logs, path: "logs", only: :index
      resources :services, path: "catalogo-servicos", except: %i[show destroy]
      resource :settings, path: "configuracoes", only: %i[show update]
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
