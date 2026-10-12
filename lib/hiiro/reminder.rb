require 'sequel'
require 'time'

class Hiiro
  class Reminder < Sequel::Model(:reminders)
    Hiiro::DB.register(self)

    FIELDS = %i[message interval sound enabled once trigger_at last_triggered created_at].freeze
    SCHEDULING_FIELDS = %i[enabled once interval trigger_at last_triggered].freeze
    class EditConflict < StandardError; end

    def self.create_table!(db)
      db.create_table?(:reminders) do
        primary_key :id
        String :message
        String :interval
        String :sound
        TrueClass :enabled
        TrueClass :once
        String :trigger_at
        String :last_triggered
        String :created_at
      end
    end

    def self.active = where(enabled: true)
    def self.due(now: Time.now) = active.order(:id).all.select { |row| row.due?(now: now) }

    def self.defaults(now: Time.now)
      { message: '', interval: '1h', sound: nil, enabled: true, once: false,
        trigger_at: nil, last_triggered: nil, created_at: now.iso8601 }
    end

    def self.add(**fields)
      values = defaults.merge(fields)
      validate_fields!(values)
      create(values)
    end

    def self.parse_time_arg(text, now: Time.now)
      return [false, nil, '1h'] if text.nil?

      if text.match?(/\A\d{12}\z/)
        # Calendar digits are not TimeInput's numeric Unix-millisecond grammar.
        calendar = Time.strptime(text, '%Y%m%d%H%M')
        return [true, TimeInput.parse(calendar.iso8601).iso8601, nil]
      end
      duration = Duration.parse(text)
      return [true, TimeInput.parse((now + duration.seconds).iso8601).iso8601, text] if duration

      [false, nil, text]
    end

    def self.set_enabled(id, enabled)
      db.transaction(mode: :immediate) do
        row = self[id]
        next unless row
        row.set(enabled: enabled)
        row.save_changes
        row
      end
    end

    def self.remove(id)
      db.transaction(mode: :immediate) do
        row = self[id]
        row&.destroy
      end
    end

    def self.clean = where(once: true, enabled: false).delete

    def self.mark_triggered(id, now: Time.now, expected_checkpoint:)
      db.transaction(mode: :immediate) do
        row = self[id]
        next unless row && row.schedule_checkpoint == expected_checkpoint && row.due?(now: now)
        yield row if block_given?
        row.set(last_triggered: now.iso8601)
        row.enabled = false if row.one_time?
        row.save_changes
        row
      end
    end

    def self.check_due(now: Time.now, notify:)
      due(now: now).filter_map do |row|
        mark_triggered(row.id, now: now, expected_checkpoint: row.schedule_checkpoint) { |current| notify.call(current) }
      end
    end

    # The baseline is only an editor conflict check, never a write authority.
    def self.apply_edit(baseline:, rows:)
      raise ArgumentError, 'Expected a YAML array of reminders' unless rows.is_a?(Array)
      original = baseline.to_h { |row| [row.fetch(:id), row] }
      seen = []
      parsed = rows.map do |input|
        raise ArgumentError, 'Each reminder must be a mapping' unless input.is_a?(Hash)
        row = input.transform_keys(&:to_sym)
        unknown = row.keys - FIELDS - [:id]
        raise ArgumentError, "Unknown reminder fields: #{unknown.join(', ')}" unless unknown.empty?
        if row.key?(:id)
          id = row[:id]
          raise ArgumentError, 'Existing reminder IDs must be unique selected integers' unless id.is_a?(Integer) && original.key?(id) && !seen.include?(id)
          seen << id
        end
        supplied = row.reject { |field, value| field == :id || (row.key?(:id) && original.fetch(row[:id])[field] == value) }
        validate_fields!(supplied)
        row
      end

      db.transaction(mode: :immediate) do
        parsed.each do |desired|
          unless desired.key?(:id)
            add(**desired)
            next
          end
          id = desired.fetch(:id)
          before = original.fetch(id)
          changes = desired.reject { |field, value| field == :id || before[field] == value }
          next if changes.empty?
          current = self[id]
          raise EditConflict, "Reminder ##{id} was removed while editing" unless current
          changes.each do |field, value|
            unless current[field] == before[field] || current[field] == value
              raise EditConflict, "Reminder ##{id} #{field} changed while editing"
            end
          end
          current.set(changes)
          current.save_changes
        end
        (original.keys - seen).each do |id|
          current = self[id]
          next unless current
          unless current.values == original.fetch(id)
            raise EditConflict, "Reminder ##{id} changed before deletion"
          end
          current.destroy
        end
      end
    end

    def self.edit(hiiro:, reminders: nil)
      baseline = reminders ? reminders.map { |row| row.values.dup } : []
      projection = reminders ? baseline : [defaults]
      input = InputFile.yaml_file(hiiro: hiiro, content: projection.map { |row| row.transform_keys(&:to_s) }.to_yaml, prefix: 'reminder-edit-')
      document = input.edit.document
      return false unless document.editor_succeeded? && document.changed? && !document.empty?
      raise document.error unless document.valid?
      apply_edit(baseline: baseline, rows: document.parsed)
      true
    ensure
      input&.cleanup
    end

    def self.validate_fields!(fields)
      raise ArgumentError, 'Unknown reminder fields' unless (fields.keys - FIELDS).empty?
      fields.each do |field, value|
        case field
        when :message
          raise ArgumentError, 'Reminder message must be nonblank text' unless value.is_a?(String) && !value.strip.empty?
        when :enabled, :once
          raise ArgumentError, "#{field} must be true or false" unless value == true || value == false
        when :interval, :sound
          raise ArgumentError, "#{field} must be text or null" unless value.nil? || value.is_a?(String)
        when :trigger_at, :last_triggered, :created_at
          next if value.nil?
          raise ArgumentError, "#{field} must be a timestamp string or null" unless value.is_a?(String) && !value.empty?
          TimeInput.parse(value)
        end
      end
    end

    def one_time? = self[:once] == true
    def interval_seconds = Duration.parse(interval)&.seconds || 3600
    def schedule_checkpoint = values.slice(*SCHEDULING_FIELDS)

    def due?(now: Time.now)
      return false unless enabled
      if one_time?
        return false if last_triggered || !trigger_at
        begin
          now >= TimeInput.parse(trigger_at).time
        rescue ArgumentError
          false
        end
      elsif last_triggered.nil?
        true
      else
        begin
          last_time = TimeInput.parse(last_triggered).time
        rescue ArgumentError
          last_time = Time.at(0)
        end
        now - last_time >= interval_seconds
      end
    end

    def display_string
      status = enabled ? '[ON]' : '[OFF]'
      sound_text = sound ? " (#{sound})" : ''
      schedule = if one_time? && trigger_at
        begin
          "ONCE @ #{TimeInput.parse(trigger_at).strftime('%Y-%m-%d %H:%M')}"
        rescue ArgumentError
          "ONCE @ #{trigger_at}"
        end
      else
        one_time? ? 'ONCE' : interval
      end
      "#{id.to_s.rjust(3)}. #{status} [#{schedule}] #{message}#{sound_text}"
    end
  end
end
