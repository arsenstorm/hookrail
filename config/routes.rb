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

  # Authenticated landing page
  root "dashboard#show"
end
