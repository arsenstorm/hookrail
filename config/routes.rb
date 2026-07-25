Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Public webhook ingest endpoint. Accepts any HTTP method.
  match "/ingest/:token", to: "ingest#create", via: :all, as: :ingest

  # Auth
  get    "login",  to: "sessions#new",     as: :login
  delete "logout", to: "sessions#destroy", as: :logout
  get    "/auth/:provider/callback", to: "sessions#create"
  get    "/auth/failure",            to: "sessions#failure"

  # Read-only event inspection + manual delivery retry
  resources :events, only: %i[index show] do
    resources :retries, only: :create
    collection do
      post :bulk_retry, to: "bulk_retries#create"
      post :bulk_replay, to: "bulk_replays#create"
    end
  end

  # Webhooks rejected by inbound signature verification
  resources :quarantined_webhooks, only: %i[index show], path: "quarantine"

  # Route management: sources, destinations, and the connections that wire them.
  resources :sources do
    member { patch :rotate_token }
  end
  resources :destinations do
    member { patch :rotate_secret }
  end
  resources :connections, only: %i[index new create edit update destroy] do
    member { patch :status, to: "connections#update_status" }
  end

  # Org-scoped API keys managed in the UI; the JSON API below authenticates with them.
  resources :api_keys, only: %i[index create destroy]

  # One alert webhook per org, mirrored by the JSON API.
  resource :alert_webhook, only: %i[show update destroy] do
    post :test
  end

  # Aggregate delivery health over a selectable window.
  get "metrics", to: "metrics#show", as: :metrics

  namespace :api do
    namespace :v1 do
      resources :sources, :destinations, only: %i[index show create update destroy]
      resources :connections, only: %i[index show create update destroy] do
        member { post :transformation_preview, to: "transformation_previews#create" }
      end
      resource :alert_webhook, only: %i[show update destroy]
      resources :events, only: %i[index show] do
        resources :attempts, only: :index
        resources :retries, only: :create
        collection do
          post :bulk_retry, to: "bulk_retries#create"
          post :bulk_replay, to: "bulk_replays#create"
        end
      end
    end
  end

  # Authenticated landing page
  root "dashboard#show"
end
