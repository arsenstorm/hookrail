# Encryption keys come from the environment, like every other secret here —
# this app has no Rails credentials file. Generate a set with
# `bin/rails db:encryption:init` and set the three variables in deployment.
#
# Development and test fall back to fixed keys so a fresh checkout runs without
# setup. A real production boot has no fallback: running without keys would
# write ciphertext nothing can read back, so it fails loudly instead.
PLACEHOLDER_ENCRYPTION_KEYS = {
  primary_key: "placeholder_primary_key_not_for_real_data",
  deterministic_key: "placeholder_deterministic_key_not_for_real_data",
  key_derivation_salt: "placeholder_key_derivation_salt_not_for_real_data"
}.freeze

# `assets:precompile` in the Dockerfile boots RAILS_ENV=production to compile
# CSS, long before any secret exists — SECRET_KEY_BASE_DUMMY is how that build
# step says so. Demanding real keys there fails the image build rather than
# catching a misconfigured deploy, which is the opposite of the point.
building_image = ENV["SECRET_KEY_BASE_DUMMY"].present?
placeholder_keys = !Rails.env.production? || building_image

Rails.application.configure do
  config.active_record.encryption.primary_key =
    ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence ||
    (PLACEHOLDER_ENCRYPTION_KEYS[:primary_key] if placeholder_keys)

  config.active_record.encryption.deterministic_key =
    ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].presence ||
    (PLACEHOLDER_ENCRYPTION_KEYS[:deterministic_key] if placeholder_keys)

  config.active_record.encryption.key_derivation_salt =
    ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence ||
    (PLACEHOLDER_ENCRYPTION_KEYS[:key_derivation_salt] if placeholder_keys)

  # Rows written before encryption was added stay readable, so deploying this
  # needs no downtime and no backfill before it boots.
  config.active_record.encryption.support_unencrypted_data = true

  if !placeholder_keys && config.active_record.encryption.primary_key.blank?
    raise "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY, _DETERMINISTIC_KEY and " \
          "_KEY_DERIVATION_SALT must be set in production."
  end
end
