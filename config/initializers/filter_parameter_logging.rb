# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # Device-flow codes are the polling credential: whoever redeems one first gets
  # the CLI token, and the CLI re-sends it every few seconds for 15 minutes.
  :device_code, :code,
  # A Slack/Discord incoming-webhook URL is itself a bearer credential — holding
  # the URL is all anyone needs to post into the channel.
  :webhook_url,
  # Free-form outbound headers on a destination: the natural home for a user's
  # own X-Api-Key, and the filter matches on key names, not values.
  :headers, :authorization
]
