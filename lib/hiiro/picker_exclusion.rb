require 'sequel'

class Hiiro
  # The one owner of picker exclusion rules. A row hides choices from the named
  # picker; it never refers to (or deletes) the resource behind a choice.
  #
  #   { id: 4, picker: 'branches', scope: 'task', scope_key: '3', mode: 'glob',
  #     field: 'name', pattern: 'wip/**', label: nil, created_at: '2026-10-13T09:00:00-04:00' }
  class PickerExclusion < Sequel::Model(:picker_exclusions)
    def self.create_table!(db)
      db.create_table?(:picker_exclusions) do
        primary_key :id
        String :picker, null: false
        String :scope, null: false
        String :scope_key
        String :mode, null: false
        String :field, null: false
        String :pattern, null: false
        String :label
        String :created_at, null: false
        index :picker
      end
    end

    # Rules that apply to this picker in this context: its picker-local rules,
    # its task or project rules for the current task or project, and every
    # global rule.
    def self.applicable(picker, context)
      clauses = [{ picker: picker, scope: 'picker' }, { scope: 'global' }]
      clauses << { picker: picker, scope: 'task', scope_key: context.task_id } if context.task_id
      clauses << { picker: picker, scope: 'project', scope_key: context.project } if context.project
      where(Sequel.|(*clauses)).order(:id).all.map(&:to_rule)
    end

    # Removes and adds in one transaction; a rule that fails validation was
    # rejected before this point, so nothing here is partial.
    def self.apply!(change)
      db.transaction(mode: :immediate) do
        ids = change.remove.map(&:id).compact
        where(id: ids).delete unless ids.empty?
        now = Time.now.iso8601
        change.add.each do |rule|
          create(picker: rule.picker, scope: rule.scope, scope_key: rule.scope_key, mode: rule.mode,
                 field: rule.field, pattern: rule.pattern, label: rule.label, created_at: now)
        end
      end
    end

    def to_rule
      Picker::Rule.new(id: id, picker: picker, scope: scope, scope_key: scope_key, mode: mode, field: field,
                       pattern: pattern, label: label, created_at: created_at)
    end

    Hiiro::DB.register(self)
  end
end
