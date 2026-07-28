# A session cookie is a bearer credential, so it needs a life span. Without
# expire_after the cookie carries no expiry at all and a copy captured once
# stays valid until secret_key_base is rotated — which signs out every user in
# every organization at the same time.
#
# The matching half is User#session_token: rotating it invalidates issued
# cookies server-side, which is what makes signing out mean something to a
# cookie that has already been stolen.
Rails.application.config.session_store :cookie_store,
  key: "_hookrail_session",
  expire_after: 14.days,
  same_site: :lax,
  secure: Rails.env.production?
