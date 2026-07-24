module EventsHelper
  def delivery_summary(event)
    attempts = event.attempts.to_a
    return "no attempts" if attempts.empty?

    "#{attempts.count(&:succeeded?)}/#{attempts.size} delivered"
  end
end
