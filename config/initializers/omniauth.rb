Rails.application.config.middleware.use OmniAuth::Builder do
  provider :github, ENV["GITHUB_CLIENT_ID"], ENV["GITHUB_CLIENT_SECRET"], scope: "user:email"
end

# Only POST may initiate the request phase (paired with omniauth-rails_csrf_protection).
OmniAuth.config.allowed_request_methods = [ :post ]
