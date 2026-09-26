require 'open3'
require 'shellwords'

class Hiiro
  # What Shell ran: argv, environment (normalized to strings), working directory.
  class CommandSpecification
    attr_reader :argv, :env, :cwd

    def initialize(*argv, env: {}, cwd: nil)
      @argv = argv.flatten
      @env  = env.transform_keys(&:to_s).transform_values(&:to_s)
      @cwd  = cwd
    end

    def preview    = Shellwords.join(argv)
    def open3_args = cwd ? [env, *argv, { chdir: cwd }] : [env, *argv]
    def to_s       = preview
  end

  class Shell
    def self.capture_output(*command, **env)
      spec = CommandSpecification.new(*command, env: env)
      stdout, _status = Open3.capture2(*spec.open3_args)
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
      spec = CommandSpecification.new(*command, env: env)
      stdout, status = Open3.capture2(*spec.open3_args)
      Result.new(stdout, status, spec: spec)
    end

    def self.run_combined(*command, **env)
      spec = CommandSpecification.new(*command, env: env)
      output, status = Open3.capture2e(*spec.open3_args)
      Result.new(output, status, spec: spec)
    end

    def self.run3(*command, **env)
      spec = CommandSpecification.new(*command, env: env)
      stdout, stderr, status = Open3.capture3(*spec.open3_args)
      Result.new(stdout, status, stderr: stderr, spec: spec)
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
    def self.stream(*command, tee: $stdout, **env)
      spec = CommandSpecification.new(*command, env: env)
      Open3.popen2(*spec.open3_args) do |stdin, stdout, wait_thr|
        stdin.close
        return Result.collect_chunks(stdout, wait_thr, tee: tee, spec: spec)
      end
    end

    def self.stream_combined(*command, tee: $stdout, **env)
      spec = CommandSpecification.new(*command, env: env)
      Open3.popen2e(*spec.open3_args) do |stdin, stdout_err, wait_thr|
        stdin.close
        return Result.collect_chunks(stdout_err, wait_thr, tee: tee, spec: spec)
      end
    end
  end

  class Result
    # Factory: reads chunks from an IO (popen handle), optionally tee-ing
    # each chunk to `tee` as it arrives. Used by Shell.stream / stream_combined.
    # Pass tee: nil to capture without printing.
    def self.collect_chunks(io, wait_thr, tee: $stdout, spec: nil)
      output = +""
      loop do
        chunk = io.readpartial(4096)
        tee&.write(chunk)
        puts chunk
        output << chunk
      rescue EOFError
        break
      end
      new(output, wait_thr.value, spec: spec)
    end

    # Matches the full ANSI/VT100 escape sequence spec:
    # cursor movement, erase, colors, SGR — everything a terminal interprets.
    # [^[] catches all single-char Fe sequences (e.g. \eM, \eD); \[...] catches CSI.
    # \x20-\x2f used instead of space-to-slash to avoid ambiguity with the / regex delimiter.
    ANSI_PATTERN = /\e(?:\[[0-?]*[\x20-\x2f]*[@-~]|[^\[])/

    attr_reader :stdout, :stderr, :status, :spec

    def initialize(stdout, status, stderr: nil, spec: nil)
      @stdout = stdout
      @stderr = stderr
      @status = status
      @spec   = spec
    end

    # The command that produced this result, when known.
    def command = spec&.preview

    def success?
      status.success?
    end

    def failed?
      !success?
    end

    def exit_code
      status.exitstatus
    end

    # Replay buffered output to the terminal with ANSI sequences intact —
    # colors, cursor movement, line clears all work as they did live.
    # Returns self so you can chain: result.display.lines
    def display(out: $stdout)
      out.write(stdout)
      out.flush
      self
    end

    # Strip ANSI escape codes for text processing or filtering.
    # Also strips bare \r (carriage-return-only, used by progress bars).
    def plain_text
      @plain_text ||= stdout.gsub(ANSI_PATTERN, '').gsub(/\r(?!\n)/, '')
    end

    # Plain text split into non-empty lines.
    def lines
      @lines ||= plain_text.lines(chomp: true)
    end
  end
end
