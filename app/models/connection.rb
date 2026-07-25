class Connection < ApplicationRecord
  belongs_to :project
  belongs_to :source
  belongs_to :destination
  has_many :attempts, dependent: :destroy

  UNHEALTHY_THRESHOLD = 5
  RULE_KEYS = %w[path http_method headers body].freeze

  scope :unhealthy, -> { where.not(unhealthy_since: nil) }

  def unhealthy? = unhealthy_since.present?

  # Counters and state flips are single atomic UPDATEs so concurrent delivery
  # jobs can't double-send an alert: whichever job's guarded UPDATE matches a
  # row "claims" the transition and enqueues the one email.
  def record_delivery_failure
    self.class.update_counters(id, consecutive_failures: 1)
    claimed = self.class.where(id: id, unhealthy_since: nil)
                  .where(consecutive_failures: UNHEALTHY_THRESHOLD..)
                  .update_all(unhealthy_since: Time.current)
    AlertMailer.connection_unhealthy(reload).deliver_later if claimed == 1
  end

  def record_delivery_success
    recovered = self.class.where(id: id).where.not(unhealthy_since: nil)
                    .update_all(unhealthy_since: nil, consecutive_failures: 0)
    if recovered == 1
      AlertMailer.connection_recovered(reload).deliver_later
    else
      self.class.where(id: id).update_all(consecutive_failures: 0)
    end
  end

  # Mirrors the unique (source_id, destination_id) DB index so a duplicate pair
  # re-renders the form with a 422 instead of raising RecordNotUnique / 500.
  validates :source_id, uniqueness: { scope: :destination_id,
            message: "is already connected to that destination" }

  # belongs_to only checks the source/destination exist, not that they are the
  # caller's. Block wiring a connection to another project's endpoints so a
  # crafted source_id/destination_id can't cross project boundaries.
  validate :endpoints_belong_to_project

  before_validation { self.routing_rule = routing_rule.to_h.compact_blank }
  validate :routing_rule_shape

  before_validation { self.transformation = transformation.presence }
  validate :transformation_compiles

  # Blank rule -> routes everything (pre-rule behavior). Criteria AND together.
  # Values compare as strings so form input matches JSON numbers and booleans.
  def routes?(event)
    rule = routing_rule.to_h
    return true if rule.blank?

    rule_path_match?(rule["path"], event.path) &&
      rule_method_match?(rule["http_method"], event.http_method) &&
      rule_headers_match?(rule["headers"], event.headers) &&
      rule_body_match?(rule["body"], event.body)
  end

  private

  def endpoints_belong_to_project
    errors.add(:source, "must belong to this project") if source && source.project_id != project_id
    errors.add(:destination, "must belong to this project") if destination && destination.project_id != project_id
  end

  def routing_rule_shape
    rule = routing_rule.to_h
    unknown = rule.keys - RULE_KEYS
    errors.add(:routing_rule, "has unknown keys: #{unknown.join(", ")}") if unknown.any?
    %w[path http_method].each do |key|
      errors.add(:routing_rule, "#{key} must be a string") if rule[key].present? && !rule[key].is_a?(String)
    end
    %w[headers body].each do |key|
      errors.add(:routing_rule, "#{key} must be an object") if rule[key].present? && !rule[key].is_a?(Hash)
    end
  end

  # Reject code that can't run before it ever gates a delivery; unchanged
  # code is not re-checked on every save.
  def transformation_compiles
    return if transformation.blank? || !transformation_changed?

    Transformation::Runner.check!(transformation)
  rescue Transformation::Error => e
    errors.add(:transformation, e.message)
  end

  def rule_path_match?(pattern, path)
    return true if pattern.blank?

    Regexp.new("\\A#{Regexp.escape(pattern).gsub("\\*", ".*")}\\z").match?(path.to_s)
  end

  def rule_method_match?(expected, http_method)
    expected.blank? || expected.casecmp?(http_method.to_s)
  end

  def rule_headers_match?(criteria, headers)
    return true if criteria.blank?

    downcased = headers.to_h.transform_keys(&:downcase)
    criteria.all? { |name, value| downcased[name.downcase].to_s == value.to_s }
  end

  # Dot paths address nested JSON objects ("data.object.status"). A body that
  # is not a JSON object fails every body criterion by design, never errors.
  def rule_body_match?(criteria, body)
    return true if criteria.blank?

    json = JSON.parse(body.to_s)
    return false unless json.is_a?(Hash)

    criteria.all? { |dot_path, expected| dig_dot_path(json, dot_path).to_s == expected.to_s }
  rescue JSON::ParserError
    false
  end

  def dig_dot_path(json, dot_path)
    dot_path.to_s.split(".").reduce(json) { |node, key| node.is_a?(Hash) ? node[key] : nil }
  end
end
