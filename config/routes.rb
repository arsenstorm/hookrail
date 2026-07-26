Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Public webhook ingest endpoint. Accepts any HTTP method.
  match "/ingest/:token", to: "ingest#create", via: :all, as: :ingest

  # Auth. Outside /app: GitHub has the callback URL registered, and the old
  # /login and /logout paths stay reachable for links already in the wild.
  get    "sign-in",  to: "sessions#new",     as: :sign_in
  delete "sign-out", to: "sessions#destroy", as: :sign_out
  get    "login",  to: redirect("/sign-in", status: 301)
  delete "logout", to: redirect("/sign-out", status: 301)
  get    "/auth/:provider/callback", to: "sessions#create"
  get    "/auth/failure",            to: "sessions#failure"

  # Browser half of the CLI device-flow login. Stays outside /app: the CLI
  # opens this URL and older CLI builds hold the unscoped one.
  get  "cli/authorize", to: "cli_authorizations#show",   as: :cli_authorize
  post "cli/authorize", to: "cli_authorizations#create"

  # The human web UI. Scoped without `as:` so every *_path helper is unchanged
  # and only the URLs move.
  scope "/app" do
    get "/", to: "dashboard#show", as: :dashboard

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

    # The per-user project and org switchers: app shell, not settings.
    post "switch_project/:id", to: "project_switches#create", as: :switch_project
    post "switch_org/:id", to: "org_switches#create", as: :switch_org

    # Revoking a CLI credential. Actioned from both the account security page
    # and the API keys page, so it stays with the app shell.
    resources :cli_tokens, only: :destroy

    # Accepting an invite: a link a non-admin follows from their inbox.
    get "invites/:token", to: "invites#show", as: :invite

    # The signed-in user's own profile and credentials.
    resource :account, only: :show do
      get :security
    end
  end

  # Org-admin settings. Same `as:`-free scoping, so only the URLs move.
  scope "/org" do
    # Creating an org is open to every signed-in user — the admin gate below
    # guards the org you're in, not the one you're making.
    get  "new", to: "organizations#new", as: :new_organization
    post "new", to: "organizations#create"

    # Team management: the members page and its invite links.
    resources :members, only: %i[index update destroy] do
      member { post :transfer_ownership, path: "transfer-ownership" }
    end
    resources :invitations, only: %i[create destroy]

    # One alert webhook per org, mirrored by the JSON API.
    resource :alert_webhook, only: %i[show update destroy], path: "alert-webhook" do
      post :test
    end

    # Org-level data retention window, mirrored by the JSON API.
    resource :retention, only: %i[show update]

    # Org-scoped API keys managed in the UI; the JSON API below authenticates with them.
    resources :api_keys, only: %i[index create destroy], path: "api-keys"

    # Project management (admin); the switcher lives with the app shell.
    resources :projects, only: %i[index create update destroy]
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

  root "pages#home"
end
