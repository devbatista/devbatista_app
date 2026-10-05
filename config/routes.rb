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

    # Comercial
    resources :leads, path: "leads" do
      member do
        patch :move, path: "etapa"
        get :lose, path: "perder", action: :new_loss
        patch :lose, path: "perder"
      end
      resource :conversion, only: %i[new create], controller: "lead_conversions", path: "conversao"
      resources :interactions, only: :create, path: "interacoes"
    end
    resources :opportunities, path: "oportunidades", except: :show do
      member do
        patch :move, path: "etapa"
        get :lose, path: "perder", action: :new_loss
        patch :lose, path: "perder"
      end
      resources :interactions, only: :create, path: "interacoes"
    end
    resources :proposals, path: "propostas" do
      member do
        patch :mark, path: "status"
        get :approve, path: "aprovar", action: :new_approval
        post :approve, path: "aprovar"
        get :reject, path: "recusar", action: :new_rejection
        patch :reject, path: "recusar"
      end
    end
    get "pipeline", to: "pipeline#show", as: :pipeline

    # Operação
    resources :projects, path: "projetos"
    resources :tasks, path: "tarefas", except: :show do
      patch :move, on: :member, path: "status"
    end
    resources :time_entries, path: "horas", except: :show
    resources :tickets, path: "chamados", except: :destroy do
      member do
        get :status, path: "status", action: :new_status
        patch :status, path: "status", action: :change_status
      end
      resources :messages, only: :create, controller: "ticket_messages", path: "mensagens"
    end

    # Financeiro
    get "financeiro", to: "finance#show", as: :finance
    get "receitas", to: "receivables#index", defaults: { visao: "receitas" }, as: :revenues
    resources :receivables, path: "contas-a-receber", except: :show do
      member do
        get :payment, path: "pagamento", action: :new_payment
        patch :payment, path: "pagamento", action: :pay
        patch :cancel, path: "cancelar"
      end
    end
    get "despesas", to: "payables#index", defaults: { visao: "despesas" }, as: :expenses
    resources :payables, path: "contas-a-pagar", except: :show do
      member do
        get :payment, path: "pagamento", action: :new_payment
        patch :payment, path: "pagamento", action: :pay
        patch :cancel, path: "cancelar"
      end
    end
    get "recorrencias", to: "recurrences#index", as: :recurrences
    post "recorrencias/executar", to: "recurrences#run", as: :run_recurrences
    resources :recurring_expenses, path: "despesas-recorrentes", only: %i[edit update] do
      patch :finish, on: :member, path: "encerrar"
    end
    resources :invoices, path: "notas-fiscais", except: :show do
      get :file, on: :member, path: "arquivo/:file_id"
    end
    resources :suppliers, path: "fornecedores", except: :show

    # Tecnologia
    resources :apps, path: "aplicacoes"
    resources :servers, path: "servidores", except: :show
    resources :domains, path: "dominios", except: :show do
      member do
        get :renewal, path: "renovacao", action: :new_renewal
        patch :renewal, path: "renovacao", action: :renew
      end
    end
    resources :databases, path: "bancos-de-dados", except: :show
    resources :integrations, path: "integracoes", except: :show
    resources :external_services, path: "servicos-externos", except: :show

    # Produtos
    get "produtos/indicadores", to: "products#indicators", as: :product_indicators
    resources :products, path: "produtos", except: :show
    resources :subscriptions, path: "assinaturas", except: :show

    # Gestão
    get "indicadores", to: "indicators#show", as: :indicators
    get "rentabilidade", to: "profitability#show", as: :profitability
    resources :reports, path: "relatorios", only: %i[index show]

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
