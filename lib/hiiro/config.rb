require 'yaml'

class Hiiro
  class Config
    BASE_DIR = File.join(Dir.home, '.config/hiiro')
    DATA_DIR = File.join(Dir.home, '.local/share/hiiro')

    class << self
      def open(file, dir: nil)
        dir_path = File.expand_path(dir || '~')
        full_path = File.expand_path(file, dir_path)
        Dir.chdir(dir_path)
        system(ENV['EDITOR'] || 'vim', full_path)
      end

      def path(relpath='')
        File.join(BASE_DIR, relpath)
      end

      def load_yaml(relpath = 'config.yml', default: {}, permitted_classes: [Symbol])
        file = path(relpath)
        return default unless File.exist?(file)

        YAML.safe_load_file(file, permitted_classes: permitted_classes) || default
      rescue StandardError
        default
      end

      def yaml_dig(relpath = 'config.yml', *keys, default: nil, permitted_classes: [Symbol])
        value = load_yaml(relpath, default: {}, permitted_classes: permitted_classes)

        keys.flatten.each do |key|
          return default unless value.is_a?(Hash)

          value =
            if value.key?(key)
              value[key]
            elsif value.key?(key.to_s)
              value[key.to_s]
            elsif key.respond_to?(:to_sym) && value.key?(key.to_sym)
              value[key.to_sym]
            else
              return default
            end
        end

        value.nil? ? default : value
      end

      def data_path(relpath='')
        File.join(DATA_DIR, relpath)
      end

      def plugin_files
        user_files = Dir.glob(File.join(plugin_dir, '*.rb'))
        user_basenames = user_files.map { |f| File.basename(f) }

        gem_plugin_dir = File.join(File.expand_path('../..', __FILE__), 'plugins')
        gem_files = Dir.exist?(gem_plugin_dir) ? Dir.glob(File.join(gem_plugin_dir, '*.rb')) : []

        fallback_files = gem_files.reject { |f| user_basenames.include?(File.basename(f)) }

        user_files + fallback_files
      end

      def plugin_dir
        config_dir('plugins')
      end

      def config_dir(subdir=nil)
        File.join(Dir.home, '.config/hiiro', *[subdir].compact).tap do |config_path|
          FileUtils.mkdir_p(config_path) unless Dir.exist?(config_path)
        end
      end
    end
  end
end
