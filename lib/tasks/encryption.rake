namespace :encryption do
  # `encrypts` only encrypts on write, so rows written before those declarations
  # landed are still plaintext in the database. Re-saving each one rewrites it
  # through the encrypting type. Idempotent, and safe to run repeatedly.
  desc "Rewrite rows written before encryption was enabled so no plaintext secrets remain"
  task backfill: :environment do
    encrypted = {
      Destination => %i[signing_secret auth],
      Source => %i[verification],
      Organization => %i[alert_webhook_secret]
    }

    encrypted.each do |model, attributes|
      rewritten = 0
      model.find_each do |record|
        # Needs a rewrite only where there is something to encrypt and it is not
        # encrypted yet — a blank value is never "already encrypted", so without
        # the presence check those rows are rewritten on every run, forever.
        pending = attributes.select do |attribute|
          record.read_attribute(attribute).present? && !record.encrypted_attribute?(attribute)
        end
        next if pending.empty?

        # Saving an unchanged record issues no UPDATE at all, so the attribute
        # has to be marked dirty or the rewrite silently does nothing.
        pending.each { |attribute| record.send(:"#{attribute}_will_change!") }
        record.save!(validate: false)
        rewritten += 1
      end
      puts "#{model.name}: rewrote #{rewritten} row(s)"
    end

    puts "Done. Once every environment reports 0, set " \
         "config.active_record.encryption.support_unencrypted_data = false."
  end
end
