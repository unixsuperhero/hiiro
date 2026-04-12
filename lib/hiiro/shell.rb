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

    def self.run(*command, **env)
      env = env.transform_keys(&:to_s).transform_values(&:to_s)
      stdout, status = Open3.capture2(env, *command)
      Result.new(stdout, status)
    end

    def self.run_combined(*command, **env)
      env = env.transform_keys(&:to_s).transform_values(&:to_s)
      output, status = Open3.capture2e(env, *command)
      Result.new(output, status)
    end

    def self.run3(*command, **env)
      env = env.transform_keys(&:to_s).transform_values(&:to_s)
      stdout, stderr, status = Open3.capture3(env, *command)
      Result.new(stdout, status, stderr: stderr)
    end

    # Stream stdout live to $stdout as chunks arrive, buffering for Result.
    # stderr passes through to the parent process (not captured).
    #
    # ~/bin/h-tds does this manually with popen2e for Chromatic:
    #
    #   Open3.popen2e('unbuffer pnpm chromatic') do |stdin, stdout_err, wait_thr|
    #     stdin.close
    #     loop do
    #       chunk = stdout_err.readpartial(4096)
    #       $stdout.write(chunk)
    #       @output << chunk
    #     rescue EOFError
    #       break
    #     end
    #     @exit_status = wait_thr.value
    #   end
    #
    # stream_combined replaces that pattern — stderr merged in, one Result back.
    def self.stream(*command, **env)
      env = env.transform_keys(&:to_s).transform_values(&:to_s)
      output = ""
      status = nil

      Open3.popen2(env, *command) do |stdin, stdout, wait_thr|
        stdin.close
        loop do
          chunk = stdout.readpartial(4096)
          $stdout.write(chunk)
          output << chunk
        rescue EOFError
          break
        end
        status = wait_thr.value
      end

      Result.new(output, status)
    end

    def self.stream_combined(*command, **env)
      env = env.transform_keys(&:to_s).transform_values(&:to_s)
      output = ""
      status = nil

      Open3.popen2e(env, *command) do |stdin, stdout_err, wait_thr|
        stdin.close
        loop do
          chunk = stdout_err.readpartial(4096)
          $stdout.write(chunk)
          output << chunk
        rescue EOFError
          break
        end
        status = wait_thr.value
      end

      Result.new(output, status)
    end
  end

  class Result
    attr_reader :stdout, :stderr, :status

    def initialize(stdout, status, stderr: nil)
      @stdout = stdout
      @stderr = stderr
      @status = status
    end

    def success?
      status.success?
    end

    def failed?
      !success?
    end

    def exit_code
      status.exitstatus
    end
  end
end
