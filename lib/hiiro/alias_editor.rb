class Hiiro
  module AliasEditor
    def editor_projection
      order(:id).all.map { |record| record.values.transform_keys(&:to_s) }
    end

    def edit(hiiro:)
      baseline = editor_projection
      input = InputFile.yaml_file(hiiro: hiiro, content: baseline.to_yaml, prefix: 'alias-edit-')
      document = input.edit.document
      return false unless document.valid? && document.changed? && !document.empty?

      apply_edit(baseline: baseline, rows: document.data)
      true
    ensure
      input&.cleanup
    end

    def apply_edit(baseline:, rows:)
      raise ArgumentError, 'Expected a YAML array of aliases' unless rows.is_a?(Array)
      originals = baseline.to_h { |row| [row.fetch('id'), row] }
      seen = []
      rows.each do |row|
        raise ArgumentError, 'Each alias must be a mapping' unless row.is_a?(Hash)
        raise ArgumentError, 'Unknown alias field' unless (row.keys - %w[id name path delete]).empty?
        raise ArgumentError, 'delete must be true or false' if row.key?('delete') && ![true, false].include?(row['delete'])
        if row.key?('id')
          id = row['id']
          raise ArgumentError, 'Unknown or duplicate alias ID' unless id.is_a?(Integer) && originals.key?(id) && !seen.include?(id)
          seen << id
        elsif row['delete']
          raise ArgumentError, 'Deletion requires a baseline alias ID'
        end
        next if row['delete']
        %w[name path].each do |field|
          raise ArgumentError, "#{field} must be a nonempty string" unless row[field].is_a?(String) && !row[field].strip.empty?
        end
      end

      db.transaction do
        rows.each do |row|
          if row.key?('id')
            original = originals.fetch(row['id'])
            changes = %w[name path].select { |field| row[field] != original[field] }
            next if !row['delete'] && changes.empty?

            current = self[row['id']]
            raise Hiiro::Error, "Alias #{row['id']} no longer exists" unless current
            compared = row['delete'] ? %w[name path] : changes
            unless compared.all? { |field| current[field.to_sym] == original[field] }
              raise Hiiro::Error, "Alias #{row['id']} changed while editing"
            end
            if row['delete']
              current.destroy
            else
              current.update(changes.to_h { |field| [field.to_sym, row[field]] })
            end
          else
            create(name: row.fetch('name'), path: row.fetch('path'))
          end
        end
      end
    end
  end
end
