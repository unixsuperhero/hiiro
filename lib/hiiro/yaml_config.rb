require 'yaml'
require 'fileutils'
require 'ostruct'

class Hiiro
  module YamlConfig
    def load_config
      return {} unless File.exist?(config_file)
      YAML.safe_load_file(config_file, permitted_classes: [Symbol]) || {}
    end

    def save_config(data)
      FileUtils.mkdir_p(File.dirname(config_file))
      File.write(config_file, YAML.dump(data))
    end

    def symbolize_keys(hash)
      hash.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
    end

    def find_by_name(name)
      configs = load_config
      names = configs.keys.map { |k| OpenStruct.new(name: k) }
      result = Hiiro::Matcher.new(names, :name).by_prefix(name)
      match = result.resolved || result.first
      return nil unless match

      matched_name = match.item.name
      { name: matched_name, **symbolize_keys(configs[matched_name]) }
    end
  end
end
