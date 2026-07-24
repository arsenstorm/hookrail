module Delivery
  Result = Struct.new(:status, :body_excerpt, :error, :duration_ms, keyword_init: true) do
    def success?
      status.present? && (200..299).cover?(status)
    end
  end
end
