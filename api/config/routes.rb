require "sidekiq/web"

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  mount Sidekiq::Web => "/sidekiq" if Rails.env.development?

  namespace :api do
    namespace :v1 do
      namespace :auth do
        post   "login",      to: "sessions#login"
        post   "mfa",        to: "sessions#mfa"
        post   "refresh",    to: "sessions#refresh"
        delete "logout",     to: "sessions#logout"
        delete "logout_all", to: "sessions#logout_all"
        get    "me",         to: "sessions#me"
        post   "otp/setup",  to: "otp#setup"
        post   "otp/enable", to: "otp#enable"
        delete "otp",        to: "otp#disable"
      end
      resources :users, only: %i[index create update destroy]
      post "users/change_password", to: "users#change_password"
      resources :clients, only: %i[index show create update] do
        resources :tax_scenarios, only: %i[index show create update destroy] do
          post :publish, on: :member
          post :infer, on: :collection
        end
      end
      resources :uploads, only: %i[create show]
      resources :fiscal_files, only: %i[index show create]
      resources :audit_runs, only: %i[index create show] do
        resources :findings, only: :index
        get "report.pdf", to: "reports#audit_run", format: false
      end
      resources :findings, only: :update
      resources :rule_overrides, only: %i[index create update destroy]
      resources :reference_row_overrides, only: %i[index create update destroy]
      get "reference_tables", to: "admin/reference_tables#index"   # leitura para qualquer usuário autenticado (nomes das tabelas)

      namespace :admin do
        resources :rules, only: %i[index show create update] do
          member do
            post :transition
            post :validate
            get :stats
          end
          resources :test_cases, controller: "rule_test_cases", only: %i[create update destroy] do
            post :run, on: :member
            post :run_all, on: :collection
          end
        end
        get "reference_tables/curation_queue", to: "reference_tables#curation_queue"
        resources :reference_tables, only: %i[index show create update] do
          post :sync, to: "reference_versions#sync", on: :member
          resources :versions, controller: "reference_versions", only: %i[show create update] do
            member do
              get :rows
              post :import
              post :publish
              post :retire
              get :diff
            end
          end
        end
      end
    end
  end
end
