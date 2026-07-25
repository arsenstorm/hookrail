class ApplicationMailer < ActionMailer::Base
  default from: "Hookrail <alerts@hookrail.dev>"
  layout "mailer"
end
