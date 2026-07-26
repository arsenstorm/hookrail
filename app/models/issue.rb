class Issue < ApplicationRecord
  belongs_to :project
  belongs_to :subject, polymorphic: true

  TYPES = %w[delivery_failure transformation_error webhook_quarantined].freeze

  # prefix: consistent with Connection's status enum.
  enum :status, { open: "open", acknowledged: "acknowledged", resolved: "resolved" },
       prefix: true, validate: true

  validates :issue_type, inclusion: { in: TYPES }

  scope :unresolved, -> { where.not(status: "resolved") }

  # One occurrence of a problem. The guarded UPDATE increments the existing
  # non-resolved issue (common case); on a miss the insert races the partial
  # unique index and the loser loops back to increment. Notifies only when a
  # new issue opens — never on increment.
  def self.record!(type:, subject:, summary:)
    keys = { issue_type: type.to_s, subject_type: subject.class.name, subject_id: subject.id }
    loop do
      bumped = unresolved.where(keys).update_all([ "count = count + 1, last_seen_at = ?", Time.current ])
      return if bumped == 1

      begin
        issue = create!(keys.merge(project_id: subject.project_id, summary: summary,
                                   first_seen_at: Time.current, last_seen_at: Time.current))
        Alerts.issue_opened(issue)
        return
      rescue ActiveRecord::RecordNotUnique
        # Lost the create race; the winner's row takes the increment next pass.
      end
    end
  end

  # Count an occurrence only while an issue is already open; never opens one.
  def self.bump!(type:, subject:)
    unresolved.where(issue_type: type.to_s, subject_type: subject.class.name, subject_id: subject.id)
              .update_all([ "count = count + 1, last_seen_at = ?", Time.current ])
  end

  def self.auto_resolve!(type:, subject:)
    unresolved.where(issue_type: type.to_s, subject_type: subject.class.name, subject_id: subject.id)
              .update_all(status: "resolved")
  end

  # Connections have no name column; render them as their route.
  def subject_name
    return "(deleted)" if subject.nil?

    subject.is_a?(Connection) ? "#{subject.source.name} → #{subject.destination.name}" : subject.name
  end
end
