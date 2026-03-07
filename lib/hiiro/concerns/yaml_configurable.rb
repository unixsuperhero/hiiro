require 'yaml'
require 'fileutils'

class Hiiro
  module YamlConfigurable
    # Load a YAML file, returning a default value if it doesn't exist.
    #
    # @param path [String] path to YAML file
    # @param default [Object] value to return if file doesn't exist
    # @return [Object] parsed YAML or default
    def load_yaml(path, default: {})
      return default unless File.exist?(path)
      YAML.safe_load_file(path, permitted_classes: [Symbol]) || default
    end

    # Save data to a YAML file, creating parent directories as needed.
    #
    # @param path [String] path to YAML file
    # @param data [Object] data to serialize
    def save_yaml(path, data)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, YAML.dump(data))
    end

    # Convert string keys to symbols in a hash.
    #
    # @param hash [Hash] hash with string keys
    # @return [Hash] hash with symbol keys
    def symbolize_keys(hash)
      return {} unless hash.is_a?(Hash)
      hash.transform_keys(&:to_sym)
    end

    # Recursively convert string keys to symbols.
    #
    # @param hash [Hash] hash with string keys
    # @return [Hash] hash with symbol keys at all levels
    def deep_symbolize_keys(hash)
      return hash unless hash.is_a?(Hash)
      hash.each_with_object({}) do |(key, value), result|
        new_key = key.is_a?(String) ? key.to_sym : key
        new_value = value.is_a?(Hash) ? deep_symbolize_keys(value) : value
        result[new_key] = new_value
      end
    end
  end
end
