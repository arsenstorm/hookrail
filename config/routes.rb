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

  # Persistent incidents with an ack/resolve lifecycle.
  resources :issues, only: %i[index show] do
    member do
      patch :acknowledge
      patch :resolve
    end
  end

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

  # Project management (admin) and the per-user project switcher.
  resources :projects, only: %i[index create update destroy]
  post "switch_project/:id", to: "project_switches#create", as: :switch_project

  # Browser half of the CLI device-flow login.
  get  "cli/authorize", to: "cli_authorizations#show",   as: :cli_authorize
  post "cli/authorize", to: "cli_authorizations#create"
  resources :cli_tokens, only: :destroy

  # One alert webhook per org, mirrored by the JSON API.
  resource :alert_webhook, only: %i[show update destroy] do
    post :test
  end

  # Org-level data retention window, mirrored by the JSON API.
  resource :retention, only: %i[show update]

  # Team management: the members page, invite links, and the org switcher.
  resources :members, only: %i[index update destroy] do
    member { post :transfer_ownership }
  end
  resources :invitations, only: %i[create destroy]
  get "invites/:token", to: "invites#show", as: :invite
  post "switch_org/:id", to: "org_switches#create", as: :switch_org

  # The signed-in user's own profile and credentials.
  resource :account, only: :show do
    get :security
  end

  namespace :api do
    namespace :v1 do
      resources :sources, :destinations, only: %i[index show create update destroy]
      resources :projects, only: :index
      resources :connections, only: %i[index show create update destroy] do
        member { post :transformation_preview, to: "transformation_previews#create" }
      end
      resource :alert_webhook, only: %i[show update destroy]
      resource :retention, only: %i[show update]
      resources :events, only: %i[index show] do
        resources :attempts, only: :index
        resources :retries, only: :create
        collection do
          post :bulk_retry, to: "bulk_retries#create"
          post :bulk_replay, to: "bulk_replays#create"
        end
      end

      namespace :cli do
        resources :device_authorizations, only: :create do
          collection { post :token }
        end
        get    "whoami", to: "sessions#whoami"
        delete "token",  to: "sessions#destroy"
        resources :listeners, only: :create
        post "attempts/:attempt_id/result", to: "attempt_results#create"
      end
    end
  end

  # Authenticated landing page
  root "dashboard#show"
end
