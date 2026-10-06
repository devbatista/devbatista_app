Rails.application.routes.draw do
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development? && defined?(LetterOpenerWeb)

  devise_for :users, path: "", path_names: { sign_in: "sign-in", sign_out: "sign-out" }

  root "dashboard#show"

  # URLs em inglês e em kebab-case: /customer-services/new, /companies/1/edit.
  # Os parâmetros de query continuam em português (?empresa=, ?periodo=).
  resources :companies, except: :destroy
  resources :contacts, except: :show do
    patch :make_primary, on: :member, path: "primary"
  end
  resources :contracts, except: :destroy
  resources :customer_services, path: "customer-services", except: %i[show destroy]
  resources :documents, only: %i[index new create show destroy]

  # Comercial
  resources :leads do
    member do
      patch :move, path: "stage"
      get :lose, action: :new_loss
      patch :lose
    end
    resource :conversion, only: %i[new create], controller: "lead_conversions"
    resources :interactions, only: :create
  end
  resources :opportunities, except: :show do
    member do
      patch :move, path: "stage"
      get :lose, action: :new_loss
      patch :lose
    end
    resources :interactions, only: :create
  end
  resources :proposals do
    member do
      patch :mark, path: "status"
      get :approve, action: :new_approval
      post :approve
      get :reject, action: :new_rejection
      patch :reject
    end
  end
  get "pipeline", to: "pipeline#show", as: :pipeline

  # Operação
  resources :projects
  resources :tasks, except: :show do
    patch :move, on: :member, path: "status"
  end
  resources :time_entries, path: "time-entries", except: :show
  resources :tickets, except: :destroy do
    member do
      get :status, action: :new_status
      patch :status, action: :change_status
    end
    resources :messages, only: :create, controller: "ticket_messages"
  end

  # Financeiro
  get "finance", to: "finance#show", as: :finance
  get "revenues", to: "receivables#index", defaults: { visao: "receitas" }, as: :revenues
  resources :receivables, except: :show do
    member do
      get :payment, action: :new_payment
      patch :payment, action: :pay
      patch :cancel
    end
  end
  get "expenses", to: "payables#index", defaults: { visao: "despesas" }, as: :expenses
  resources :payables, except: :show do
    member do
      get :payment, action: :new_payment
      patch :payment, action: :pay
      patch :cancel
    end
  end
  get "recurrences", to: "recurrences#index", as: :recurrences
  post "recurrences/run", to: "recurrences#run", as: :run_recurrences
  resources :recurring_expenses, path: "recurring-expenses", only: %i[edit update] do
    patch :finish, on: :member
  end
  resources :invoices, except: :show do
    get :file, on: :member, path: "file/:file_id"
  end
  resources :suppliers, except: :show

  # Tecnologia
  resources :apps
  resources :servers, except: :show
  resources :domains, except: :show do
    member do
      get :renewal, action: :new_renewal
      patch :renewal, action: :renew
    end
  end
  resources :databases, except: :show
  resources :integrations, except: :show
  resources :external_services, path: "external-services", except: :show

  # Produtos
  get "products/indicators", to: "products#indicators", as: :product_indicators
  resources :products, except: :show
  resources :subscriptions, except: :show

  # Gestão
  get "indicators", to: "indicators#show", as: :indicators
  get "profitability", to: "profitability#show", as: :profitability
  resources :reports, only: %i[index show]

  resources :notifications, only: %i[index update] do
    patch :read_all, on: :collection, path: "read-all"
    patch :preferences, on: :collection
  end
  get "search", to: "search#index", as: :search

  # Troca da própria senha, aberta a todo usuário logado.
  get "account/password", to: "account_passwords#edit", as: :edit_account_password
  patch "account/password", to: "account_passwords#update", as: :account_password

  namespace :admin do
    resources :users, except: %i[show destroy] do
      patch :toggle_active, on: :member, path: "activation"
    end
    resource :permissions, only: %i[show update]
    resources :audit_logs, path: "logs", only: :index
    resources :services, path: "service-catalog", except: %i[show destroy]
    resource :settings, only: %i[show update]
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
