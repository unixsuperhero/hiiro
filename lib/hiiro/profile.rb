require 'yaml'
require 'shellwords'
require_relative 'config'
require_relative 'error'

class Hiiro
  # Personal recipe policy: output directories, editor recipes, and adapter
  # commands that belong to one person's machine rather than to the command.
  # One YAML file, ~/.config/hiiro/profile.yml, with a section per recipe:
  #
  #   casts:
  #     dir: ~/notes/yt/casts
  #     editor: safe_nvim
  #
  #   profile = Hiiro::Profile.load
  #   casts = profile.section('casts', 'dir' => '~/casts', 'editor' => ENV['EDITOR'])
  #   casts.path('dir')     # => "/Users/me/notes/yt/casts" (expanded)
  #   casts.argv('editor')  # => ["safe_nvim"] (a String is split like a shell word list)
  #   casts['dir']          # => "~/notes/yt/casts" (as written)
  class Profile
    FILE = 'profile.yml'

    def self.path = Config.path(FILE)

    def self.load(path = self.path)
      data = File.exist?(path) ? YAML.safe_load_file(path) : {}
      data ||= {}
      raise Error, "#{path}: expected a mapping of sections" unless data.is_a?(Hash)

      new(data, path)
    rescue Psych::SyntaxError => e
      raise Error, "#{path}: #{e.message}"
    end

    attr_reader :data, :path

    def initialize(data = {}, path = nil)
      @data = data
      @path = path
    end

    # The named section over its defaults. A key present in the file wins,
    # even when its value is empty.
    def section(name, defaults = {})
      value = data.fetch(name.to_s, {}) || {}
      raise Error, "#{path}: section #{name} must be a mapping" unless value.is_a?(Hash)

      Section.new(name.to_s, defaults.transform_keys(&:to_s).merge(value.transform_keys(&:to_s)), path)
    end

    Section = Struct.new(:name, :values, :file) do
      def [](key) = values[key.to_s]
      def key?(key) = values.key?(key.to_s)

      def path(key)
        value = self[key]
        value.nil? || value.to_s.empty? ? nil : File.expand_path(value.to_s)
      end

      # An argv recipe: a YAML list is used as written, a String is split into
      # words (never run through a shell).
      def argv(key)
        value = self[key]
        case value
        when nil then []
        when Array then value.map(&:to_s)
        else Shellwords.split(value.to_s)
        end
      end

      def fetch!(key)
        value = self[key]
        raise Error, "#{name}.#{key} is not set (#{file || Profile.path})" if value.nil? || value.to_s.empty? || value == []

        value
      end
    end
  end
end
