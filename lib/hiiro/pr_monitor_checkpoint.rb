require 'sequel'

class Hiiro
  # What the PR monitor last acted on, per qualified PR and channel. Written
  # only by Hiiro::PrMonitor, after its effect succeeded (or when there was
  # nothing to do), so a failed delivery is attempted again next cycle.
  #
  #   { repo: 'team/one', number: 42, channel: 'checks', head_sha: 'aaaa…', state: 'failing',
  #     observed_at: '2026-10-13T10:00:00Z', delivered_at: '2026-10-13T10:00:01Z', detail: 'notified' }
  class PrMonitorCheckpoint < Sequel::Model(:pr_monitor_checkpoints)
    def self.create_table!(db)
      db.create_table?(:pr_monitor_checkpoints) do
        primary_key :id
        String :repo, null: false
        Integer :number, null: false
        String :channel, null: false     # checks | review | dependencies | fix | ready
        String :head_sha
        String :state, null: false
        String :observed_at, null: false
        String :delivered_at             # nil: recorded without an effect (baseline or not notable)
        String :detail
        unique %i[repo number channel]
      end
    end

    def self.for(reference) = where(repo: reference.repo.path, number: reference.number).all.to_h { |row| [row.channel, row] }

    def self.record!(reference, channel, head_sha:, state:, delivered: false, detail: nil)
      now = Time.now.utc.iso8601
      key = { repo: reference.repo.path, number: reference.number, channel: channel }
      values = { head_sha: head_sha, state: state, observed_at: now, delivered_at: (now if delivered), detail: detail }
      db.transaction(mode: :immediate) do
        where(key).update(values).positive? || insert(key.merge(values))
      end
    end

    Hiiro::DB.register(self)
  end
end
