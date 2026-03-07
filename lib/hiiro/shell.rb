require 'open3'

class Hiiro
  class Shell
    def self.capture_output(*command, **env)
      env = env.transform_keys(&:to_s).transform_values(&:to_s)

      stdout, status = Open3.capture2(env, *command)
      stdout
    end

    def self.pipe_lines(lines, *command)
      content = lines.is_a?(Array) ? lines.join("\n") : lines.to_s

      pipe(content, *command)
    end

    def self.pipe(content, *command)
      selected, status = Open3.capture2(*command, stdin_data: content)

      return nil unless status.success?

      selected&.chomp
    end
  end
end
