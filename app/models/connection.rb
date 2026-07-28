class Connection < ApplicationRecord
  belongs_to :project
  belongs_to :source
  belongs_to :destination
  has_many :attempts, dependent: :destroy
  has_many :issues, as: :subject, dependent: :destroy

  UNHEALTHY_THRESHOLD = 5
  RULE_KEYS = %w[path http_method headers body].freeze
  RULE_OPERATORS = %w[gt gte lt lte neq contains in exists].freeze
  NUMERIC_OPERATORS = { "gt" => :>, "gte" => :>=, "lt" => :<, "lte" => :<= }.freeze
  RETRY_POLICY_KEYS = %w[strategy interval max_attempts].freeze
  RETRY_MAX_ATTEMPTS = 50
  RETRY_MAX_SPAN = 7.days

  scope :unhealthy, -> { where.not(unhealthy_since: nil) }
  # A disabled connection isn't delivering, so its last health is stale — the
  # banner wants the ones still trying. Paused counts: it can resume.
  scope :actively_unhealthy, -> { unhealthy.where.not(status: "disabled") }

  # prefix: the legacy `active` boolean column still exists (kept for deploy
  # overlap), so bare enum methods would collide with `active?`.
  enum :status, { active: "active", paused: "paused", disabled: "disabled" },
       prefix: true, validate: true

  # Status transitions carry side effects: resuming releases held deliveries,
  # disabling cancels anything queued. after_update_commit so a released job
  # can't fire before the new status is visible.
  after_update_commit :apply_status_transition, if: :saved_change_to_status?

  def unhealthy? = unhealthy_since.present?

  # Counters and state flips are single atomic UPDATEs so concurrent delivery
  # jobs can't double-send an alert: whichever job's guarded UPDATE matches a
  # row "claims" the transition and enqueues the one email.
  def record_delivery_failure
    self.class.update_counters(id, consecutive_failures: 1)
    claimed = self.class.where(id: id, unhealthy_since: nil)
                  .where(consecutive_failures: UNHEALTHY_THRESHOLD..)
                  .update_all(unhealthy_since: Time.current)
    if claimed == 1
      Alerts.connection_unhealthy(reload)
      Issue.record!(type: :delivery_failure, subject: self,
                    summary: "#{consecutive_failures} consecutive delivery failures")
    else
      Issue.bump!(type: :delivery_failure, subject: self)
    end
  end

  def record_delivery_success
    recovered = self.class.where(id: id).where.not(unhealthy_since: nil)
                    .update_all(unhealthy_since: nil, consecutive_failures: 0)
    if recovered == 1
      Alerts.connection_recovered(reload)
      Issue.auto_resolve!(type: :delivery_failure, subject: self)
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

  # Normalizes Parameters / symbol keys to a plain string-keyed hash; {} clears.
  before_validation { self.retry_policy = retry_policy.to_h.stringify_keys.presence }
  validate :retry_policy_shape

  # Blank rule -> routes everything (pre-rule behavior). Criteria AND together.
  # Scalar values compare as strings so form input matches JSON numbers and
  # booleans; an object value is an operator expression (gt/gte/lt/lte/neq/
  # contains/in/exists) whose operators AND together.
  def routes?(event)
    rule = routing_rule.to_h
    return true if rule.blank?

    rule_path_match?(rule["path"], event.path) &&
      rule_method_match?(rule["http_method"], event.http_method) &&
      rule_headers_match?(rule["headers"], event.headers) &&
      rule_body_match?(rule["body"], event.body)
  end

  private

  def apply_status_transition
    previous, current = saved_change_to_status
    release_held_deliveries if previous == "paused" && current == "active"
    cancel_queued_deliveries if current == "disabled"
  end

  # Resume: held slots flip back to pending and re-enqueue in original event
  # order. ponytail: per-row UPDATE + enqueue; batch if resumes grow past a
  # few thousand held rows.
  def release_held_deliveries
    attempts.held.joins(:event).order("events.received_at, events.id").each do |attempt|
      attempt.update!(status: :pending, attempted_at: Time.current)
      DeliverEventJob.perform_later(attempt.event_id, id, replay: attempt.replay)
    end
  end

  # Disable: held/pending rows never sent anything, so cancelling them is
  # deletion, not a terminal status. In-flight scheduled retry jobs die in
  # DeliverEventJob's status guard instead.
  def cancel_queued_deliveries
    attempts.where(status: %w[held pending]).destroy_all
  end

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

    %w[headers body].each do |key|
      next unless rule[key].is_a?(Hash)

      rule[key].each do |name, value|
        next unless value.is_a?(Hash)

        errors.add(:routing_rule, "#{key}.#{name}: operator object must not be empty") if value.empty?
        value.each do |op, arg|
          errors.add(:routing_rule, "#{key}.#{name} has unknown operator: #{op}") unless RULE_OPERATORS.include?(op.to_s)
          errors.add(:routing_rule, "#{key}.#{name}: in must be an array") if op.to_s == "in" && !arg.is_a?(Array)
          errors.add(:routing_rule, "#{key}.#{name}: exists must be true or false") if op.to_s == "exists" && ![ true, false ].include?(arg)
        end
      end
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

  # Caps: at most 50 attempts, and no retry scheduled beyond 7 days after the
  # first attempt — enforced at save time so a delivery never carries an
  # unbounded retry tail.
  def retry_policy_shape
    policy = retry_policy
    return if policy.blank?

    unknown = policy.keys - RETRY_POLICY_KEYS
    errors.add(:retry_policy, "has unknown keys: #{unknown.join(", ")}") if unknown.any?

    strategy, interval, max_attempts = policy.values_at("strategy", "interval", "max_attempts")
    errors.add(:retry_policy, "strategy must be linear or exponential") unless %w[linear exponential].include?(strategy)
    errors.add(:retry_policy, "interval must be a positive integer of seconds") unless interval.is_a?(Integer) && interval.positive?
    unless max_attempts.is_a?(Integer) && max_attempts.between?(1, RETRY_MAX_ATTEMPTS)
      errors.add(:retry_policy, "max_attempts must be an integer between 1 and #{RETRY_MAX_ATTEMPTS}")
    end
    return if errors[:retry_policy].any?

    span = interval * (strategy == "exponential" ? 2**(max_attempts - 1) - 1 : max_attempts - 1)
    errors.add(:retry_policy, "schedule spans more than 7 days") if span.seconds > RETRY_MAX_SPAN
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
    criteria.all? { |name, expected| criterion_match?(downcased[name.downcase], expected) }
  end

  # Dot paths address nested JSON objects ("data.object.status"). A body that
  # is not a JSON object fails every body criterion by design, never errors.
  def rule_body_match?(criteria, body)
    return true if criteria.blank?

    json = JSON.parse(body.to_s)
    return false unless json.is_a?(Hash)

    criteria.all? { |dot_path, expected| criterion_match?(dig_dot_path(json, dot_path), expected) }
  rescue JSON::ParserError
    false
  end

  # Scalar expected -> exact string compare (pre-operator behavior). A Hash is
  # an operator expression; every operator in it must match (AND).
  def criterion_match?(actual, expected)
    return actual.to_s == expected.to_s unless expected.is_a?(Hash)

    expected.all? { |op, arg| operator_match?(op, actual, arg) }
  end

  def operator_match?(op, actual, arg)
    case op
    when "gt", "gte", "lt", "lte"
      a = Float(actual.to_s, exception: false)
      b = Float(arg.to_s, exception: false)
      a && b ? a.public_send(NUMERIC_OPERATORS.fetch(op), b) : false
    when "neq" then actual.to_s != arg.to_s
    when "contains" then actual.to_s.include?(arg.to_s)
    when "in" then Array(arg).any? { |candidate| actual.to_s == candidate.to_s }
    when "exists" then arg == !actual.nil?
    else false
    end
  end

  def dig_dot_path(json, dot_path)
    dot_path.to_s.split(".").reduce(json) { |node, key| node.is_a?(Hash) ? node[key] : nil }
  end
end
