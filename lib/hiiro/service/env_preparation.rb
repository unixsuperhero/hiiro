require 'fileutils'

class Hiiro
  class ServiceManager
    # Handles env file preparation for a service.
    # Copies base templates and injects variation values.
    class EnvPreparation
      ENV_TEMPLATES_DIR = File.join(Dir.home, '.config', 'hiiro', 'env_templates')

      attr_reader :service, :variation_overrides

      def initialize(service, variation_overrides: {})
        @service = service
        @variation_overrides = variation_overrides
      end

      # Execute the env preparation process.
      #
      # @return [void]
      def call
        base_dir = base_dir_path
        service.env_file_configs.each do |efc|
          prepare_single_env(base_dir, efc)
        end
      end

      # Alias for backwards compatibility
      alias_method :execute, :call

      private

      def base_dir_path
        base = service.base_dir
        return Dir.pwd if base.nil? || base.to_s.empty?

        git_root = `git rev-parse --show-toplevel 2>/dev/null`.chomp
        root = git_root.empty? ? Dir.pwd : git_root
        File.join(root, base)
      end

      def prepare_single_env(base_dir, efc)
        env_file = efc[:env_file]
        base_env = efc[:base_env]
        env_vars = efc[:env_vars]

        copy_base_template(base_dir, base_env, env_file) if base_env && env_file
        inject_variations(base_dir, env_file, env_vars) if env_vars && env_file
      end

      def copy_base_template(base_dir, base_env, env_file)
        src = File.join(ENV_TEMPLATES_DIR, base_env)
        dest = File.join(base_dir, env_file)
        if File.exist?(src)
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(src, dest)
        end
      end

      def inject_variations(base_dir, env_file, env_vars)
        dest = File.join(base_dir, env_file)
        lines = File.exist?(dest) ? File.readlines(dest) : []

        env_vars.each do |var_name, var_config|
          var_config = symbolize_keys(var_config) if var_config.is_a?(Hash)
          variations = var_config.is_a?(Hash) && (var_config[:variations] || var_config['variations'])
          next unless variations

          variation = (variation_overrides[var_name] || variation_overrides[var_name.to_sym] || 'local').to_s
          value = variations[variation]
          next unless value

          replaced = false
          lines.map! do |line|
            if line.match?(/\A#{Regexp.escape(var_name.to_s)}=/)
              replaced = true
              "#{var_name}=#{value}\n"
            else
              line
            end
          end
          lines << "#{var_name}=#{value}\n" unless replaced
        end

        File.write(dest, lines.join)
      end

      def symbolize_keys(hash)
        hash.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
      end

      # Backwards compatibility alias
      alias_method :resolve_base_dir, :base_dir_path
    end
  end
end
