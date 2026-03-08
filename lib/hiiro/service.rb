class Hiiro
  class Service
    attr_reader :name, :config

    def initialize(name:, **config)
      @name = name
      @config = config
    end

    def base_dir
      config[:base_dir]
    end

    def host
      config[:host] || 'localhost'
    end

    def port
      config[:port]
    end

    def url
      return nil unless port
      "http://#{host}:#{port}"
    end

    def start_command
      config[:start]
    end

    def stop_command
      config[:stop]
    end

    def init_commands
      Array(config[:init] || [])
    end

    def cleanup_commands
      Array(config[:cleanup] || [])
    end

    def env_file
      config[:env_file]
    end

    def base_env
      config[:base_env]
    end

    def env_vars
      config[:env_vars]
    end

    def env_files
      config[:env_files]
    end

    def to_h
      { name: name, **config }
    end

    def [](key)
      return name if key == :name
      config[key]
    end
  end
end
