require 'shellwords'

class Hiiro
  # Per-table shell command templates keyed by a single letter.
  class TableActions
    DEFAULTS = { 'o' => 'open {value}', 'y' => 'pbcopy <<< {value}' }.freeze

    def self.load(path = Config.path('tables.yml'))
      config = File.exist?(path) ? YAML.safe_load_file(path) : nil
      new(config || {})
    end

    def initialize(config)
      @config = config.to_h { |table, actions| [table.to_s, (actions || {}).to_h { |k, v| [k.to_s, v] }] }
    end

    def for(entry) = DEFAULTS.merge(@config.fetch(entry.resource_type.to_s, {}))

    def command(letter, entry)
      template = self.for(entry)[letter.to_s]
      return nil unless template

      fields = { 'value' => entry.value, 'name' => entry.name, 'table' => entry.resource_type }
      template.gsub(/\{(value|name|table)\}/) { Shellwords.escape(fields[$1].to_s) }
    end

    def run(letter, entry)
      cmd = command(letter, entry)
      system('/bin/sh', '-c', cmd) if cmd
      cmd
    end
  end
end
