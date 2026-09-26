class Hiiro
  # A service entry from services.yml, read once. Raw config is retained;
  # every field is an answer rather than a hash lookup at each call site.
  class ServiceDefinition
    def self.from_config(name, hash, root:, cwd: Dir.pwd)
      new(name: name, config: (hash || {}).transform_keys(&:to_sym), root: root, cwd: cwd)
    end

    attr_reader :name, :config, :root, :cwd

    def initialize(name:, config:, root:, cwd: Dir.pwd)
      @name = name
      @config = config
      @root = root
      @cwd = cwd
    end

    def group? = false

    # Relative base_dir sits under the git root; no base_dir means the cwd.
    def base_directory
      base = config[:base_dir]
      base.nil? || base.to_s.empty? ? cwd : File.join(root, base)
    end

    def host = config[:host] || 'localhost'
    def port = config[:port]
    def url  = port && "http://#{host}:#{port}"

    def init_commands    = Array(config[:init] || [])
    def start_command    = config[:start]
    def stop_command     = config[:stop]
    def cleanup_commands = Array(config[:cleanup] || [])

    # Both the env_files: [] shape and the legacy env_file/base_env/env_vars trio.
    def environment_files
      specs = if config[:env_files]
        Array(config[:env_files]).map { |ef| ef.is_a?(Hash) ? ef.transform_keys(&:to_sym) : {} }
      elsif config[:env_file] || config[:base_env] || config[:env_vars]
        [{ env_file: config[:env_file], base_env: config[:base_env], env_vars: config[:env_vars] }]
      else
        []
      end
      specs.map { |spec| EnvironmentFile.from_spec(spec, service: self) }
    end
  end

  # A `services:` group entry: named members with per-member variation overrides.
  class ServiceGroup
    def self.group_config?(hash) = hash.is_a?(Hash) && hash.key?('services')

    def self.from_config(name, hash)
      raw = (hash || {}).transform_keys(&:to_sym)
      members = Array(raw[:services]).filter_map do |member|
        next unless member.is_a?(Hash)
        service_name = member['name'] || member[:name]
        next unless service_name
        { service_name: service_name, overrides: member['use'] || member[:use] || {} }
      end
      new(name: name, members: members)
    end

    attr_reader :name, :members

    def initialize(name:, members:)
      @name = name
      @members = members
    end

    def group? = true
    def service_names = members.map { |m| m[:service_name] }
    def overrides_for(service_name) = members.find { |m| m[:service_name] == service_name }&.fetch(:overrides) || {}
  end

  # One env file a service writes before starting: template, destination,
  # and the variables whose values vary by named variation.
  class EnvironmentFile
    DEFAULT_VARIATION = 'local'

    def self.from_spec(spec, service:, templates_dir: ServiceManager::ENV_TEMPLATES_DIR)
      new(spec: spec, service: service, templates_dir: templates_dir)
    end

    attr_reader :spec, :service, :templates_dir

    def initialize(spec:, service:, templates_dir:)
      @spec = spec
      @service = service
      @templates_dir = templates_dir
    end

    def destination_path = spec[:env_file] && File.join(service.base_directory, spec[:env_file])
    def template_path    = spec[:base_env] && File.join(templates_dir, spec[:base_env])

    # { 'VAR' => { 'local' => value, 'staging' => value } } for vars that declare variations.
    def variables
      (spec[:env_vars] || {}).each_with_object({}) do |(var_name, var_config), out|
        variations = var_config.is_a?(Hash) && (var_config['variations'] || var_config[:variations])
        out[var_name] = variations if variations
      end
    end

    def variations_for(var) = variables[var]

    def selected_variation(var, overrides)
      (overrides[var] || overrides[var.to_sym] || DEFAULT_VARIATION).to_s
    end

    # { 'VAR' => value } for every variable whose selected variation exists.
    def effective_values(overrides)
      variables.each_with_object({}) do |(var_name, variations), out|
        value = variations[selected_variation(var_name, overrides)]
        out[var_name] = value if value
      end
    end

    # existing_lines with VAR= lines replaced (or appended) for effective_values.
    def desired_content(existing_lines, overrides)
      lines = existing_lines.dup
      effective_values(overrides).each do |var_name, value|
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
      lines
    end
  end
end
