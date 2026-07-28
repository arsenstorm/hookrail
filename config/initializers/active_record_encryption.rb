# Encryption keys come from the environment, like every other secret here —
# this app has no Rails credentials file. Generate a set with
# `bin/rails db:encryption:init` and set the three variables in deployment.
#
# Development and test fall back to fixed keys so a fresh checkout runs without
# setup. Production has no fallback: booting without keys would silently write
# unreadable ciphertext, so it fails loudly instead.
DEVELOPMENT_ENCRYPTION_KEYS = {
  primary_key: "development_only_primary_key_do_not_use_in_production",
  deterministic_key: "development_only_deterministic_key_do_not_use_in_prod",
  key_derivation_salt: "development_only_key_derivation_salt_do_not_use_prod"
}.freeze

Rails.application.configure do
  config.active_record.encryption.primary_key =
    ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence ||
    (DEVELOPMENT_ENCRYPTION_KEYS[:primary_key] unless Rails.env.production?)

  config.active_record.encryption.deterministic_key =
    ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].presence ||
    (DEVELOPMENT_ENCRYPTION_KEYS[:deterministic_key] unless Rails.env.production?)

  config.active_record.encryption.key_derivation_salt =
    ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence ||
    (DEVELOPMENT_ENCRYPTION_KEYS[:key_derivation_salt] unless Rails.env.production?)

  # Rows written before encryption was added stay readable, so deploying this
  # needs no downtime and no backfill before it boots.
  config.active_record.encryption.support_unencrypted_data = true

  if Rails.env.production? && config.active_record.encryption.primary_key.blank?
    raise "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY, _DETERMINISTIC_KEY and " \
          "_KEY_DERIVATION_SALT must be set in production."
  end
end
