Rails.application.routes.draw do
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development? && defined?(LetterOpenerWeb)

  devise_for :users, path: "", path_names: { sign_in: "sign-in", sign_out: "sign-out" }

  root "dashboard#show"

  # Link "Ver proposta" do e-mail ao cliente, sem login (token assinado; pode conter "/").
  get "p/*token", to: "proposal_views#show", as: :proposal_view, format: false

  # URLs em inglês e em kebab-case, agrupadas como o menu: /commercial/leads, /operations/time-entries.
  # Cada grupo é um módulo de controllers (Commercial::LeadsController), mas os helpers não levam
  # o prefixo (leads_path, form_with model: @lead). Os parâmetros de query continuam em português.

  scope module: :commercial, path: "commercial" do
    resources :leads do
      member do
        patch :move, path: "stage"
        get :lose, action: :new_loss
        patch :lose
      end
      resource :conversion, only: %i[new create], controller: "lead_conversions"
      resources :interactions, only: %i[new create]
    end
    resources :opportunities, except: :show do
      member do
        patch :move, path: "stage"
        get :lose, action: :new_loss
        patch :lose
      end
      resources :interactions, only: %i[new create]
    end
    resources :proposals do
      member do
        patch :mark, path: "status"
        get :approve, action: :new_approval
        post :approve
        get :reject, action: :new_rejection
        patch :reject
        get :pdf
        get :deliver, action: :new_delivery
        post :deliver
      end
    end
    get "pipeline", to: "pipeline#show", as: :pipeline
  end

  scope module: :customers, path: "customers" do
    resources :companies, except: :destroy
    resources :contacts, except: :show do
      patch :make_primary, on: :member, path: "primary"
    end
    resources :contracts, except: :destroy
    resources :customer_services, path: "customer-services", except: %i[show destroy]
  end

  scope module: :operations, path: "operations" do
    resources :projects
    resources :tasks, except: :show do
      patch :move, on: :member, path: "status"
    end
    resources :tickets, except: :destroy do
      member do
        get :status, action: :new_status
        patch :status, action: :change_status
      end
      resources :messages, only: :create, controller: "ticket_messages"
    end
    resources :time_entries, path: "time-entries", except: :show
  end

  get "finance", to: "finance/dashboard#show", as: :finance
  scope module: :finance, path: "finance" do
    get "revenues", to: "receivables#index", defaults: { visao: "receitas" }, as: :revenues
    get "expenses", to: "payables#index", defaults: { visao: "despesas" }, as: :expenses
    resources :receivables, except: :show do
      member do
        get :payment, action: :new_payment
        patch :payment, action: :pay
        patch :cancel
      end
    end
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
  end

  # WhatsApp → Conversas (/whatsapp/conversations) e Templates (/whatsapp/templates).
  # Vínculo da conversa com o CRM: /conversations/:id/link (vincular e desvincular) e /lead (criar lead).
  scope "whatsapp" do
    resources :whatsapp_conversations, path: "conversations", only: %i[index show] do
      member do
        get :messages
        get :panel
        post :read
      end
      resources :whatsapp_messages, path: "messages", only: :create
      resource :link, only: %i[new create destroy], controller: "whatsapp_conversation_links"
      resource :lead, only: %i[new create], controller: "whatsapp_conversation_leads"
    end
    resources :whatsapp_messages, path: "messages", only: [] do
      member do
        post :retry
        get :media
      end
    end
    resources :whatsapp_templates, path: "templates" do
      post :sync, on: :collection
    end
  end

  scope module: :technology, path: "technology" do
    resources :apps
    resources :servers, except: :show
    resources :domains, except: :show do
      member do
        get :renewal, action: :new_renewal
        patch :renewal, action: :renew
      end
    end
    resources :databases, except: :show
    # Números do WhatsApp (Embedded Signup), em Integrações → WhatsApp.
    resources :whatsapp_accounts, path: "integrations/whatsapp", only: :index do
      collection do
        post :connect
        post :signup_event, path: "signup-event"
      end
      member do
        post :register
        post :activate
      end
    end
    resources :integrations, except: :show
    resources :external_services, path: "external-services", except: :show
  end

  # Os produtos ficam na raiz do grupo (/products, /products/1/edit).
  scope module: :products, path: "products" do
    get "indicators", to: "products#indicators", as: :product_indicators
    resources :subscriptions, except: :show
    resources :products, path: "", except: :show
  end

  scope module: :management, path: "management" do
    resources :suppliers, except: :show
    resources :documents, only: %i[index new create show destroy]
    resources :reports, only: %i[index show]
    get "indicators", to: "indicators#show", as: :indicators
    get "profitability", to: "profitability#show", as: :profitability
  end

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

  # Servidor MCP, para o conector do Claude (docs/specs/mcp-comercial/README.md).
  # O lambda resolve Mcp::Endpoint a cada requisição, para o reload do código valer em desenvolvimento.
  match "mcp", to: ->(env) { Mcp::Endpoint.call(env) }, via: %i[get post delete], as: :mcp

  # OAuth do MCP: /oauth/authorize, /oauth/token, /oauth/revoke e /oauth/introspect. Os apps
  # são cadastrados pela task mcp:oauth_app, então as telas de apps do Doorkeeper ficam de fora.
  use_doorkeeper do
    skip_controllers :applications, :authorized_applications, :token_info
  end
  # Descoberta do OAuth pelo cliente MCP (RFC 9728 e RFC 8414).
  scope ".well-known", controller: "oauth_metadata", format: false do
    get "oauth-protected-resource(/mcp)", action: :protected_resource, as: :oauth_protected_resource
    get "oauth-authorization-server", action: :authorization_server, as: :oauth_authorization_server
  end

  # Webhook da Cloud API do WhatsApp (docs/specs/whatsapp), público: a Meta assina os eventos.
  scope "webhooks", module: :webhooks, format: false do
    get "whatsapp", to: "whatsapp#verify", as: :whatsapp_webhook
    post "whatsapp", to: "whatsapp#receive", as: nil
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
