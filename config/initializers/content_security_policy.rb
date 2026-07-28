# Be sure to restart your server when you modify this file.
#
# Defence in depth behind Rails' output escaping: this app stores bodies and
# headers posted by arbitrary third parties and renders them back, so if an
# escaping bug ever lands, script-src is what stops it becoming account
# takeover.
#
# Scripts are nonce-only — no 'unsafe-inline', which is the whole point;
# importmap and the pre-paint theme script both carry the nonce. Styles do
# allow inline, because Turbo and the chart code set style attributes and
# locking that down buys far less than locking down script.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri    :self
    # Browsers apply form-action to every hop of a redirect chain, so the OAuth
    # kickoff (POST /auth/github, which 302s to github.com) needs GitHub listed
    # even though the form itself posts same-origin.
    policy.form_action :self, "https://github.com"
    policy.frame_ancestors :none
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self, :unsafe_inline, "https://rsms.me"
    policy.font_src    :self, :data, "https://rsms.me"
    # GitHub avatars, plus data: for inline SVG/PNG.
    policy.img_src     :self, :data, "https://avatars.githubusercontent.com"
    # :self covers same-origin ws:// for Action Cable.
    policy.connect_src :self
  end

  # A per-request nonce lets the importmap and the theme script run while
  # everything else inline stays blocked.
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]
end
