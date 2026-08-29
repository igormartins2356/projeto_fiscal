require "sidekiq/web"

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  mount Sidekiq::Web => "/sidekiq" if Rails.env.development?

  namespace :api do
    namespace :v1 do
      resources :clients, only: :index
      resources :uploads, only: %i[create show]
      resources :audit_runs, only: %i[index create show] do
        resources :findings, only: :index
      end
      resources :findings, only: :update
    end
  end
end
