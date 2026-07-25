class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Postgres text/jsonb columns reject \0 bytes and invalid UTF-8 outright, so
  # any column holding wire data (inbound webhooks, HTTP responses, JS transform
  # output) must scrub before write or the INSERT/UPDATE raises.
  DB_TEXT = ->(s) { s.to_s.dup.force_encoding(Encoding::UTF_8).scrub.delete("\0") }
end
