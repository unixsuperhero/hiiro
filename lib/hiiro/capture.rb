require 'sequel'
require 'fileutils'
require 'json'
require 'securerandom'
require 'time'
require_relative 'shell'

class Hiiro
  class Capture < Sequel::Model(:captures)
    Hiiro::DB.register(self)

    def self.create_table!(db)
      db.create_table?(:captures) do
        primary_key :id
        String :name, null: false
        String :path, null: false
        String :command
        Integer :exit_status
      end
    end

    # Run evidence: where and when it ran, how it ended, and which task/context chose the directory.
    EVIDENCE_COLUMNS = %i[source run_id cwd started_at finished_at outcome exit_signal task_name context_json].freeze

    def self.migrate!(db)
      missing = EVIDENCE_COLUMNS - db.schema(:captures).map(&:first)
      db.alter_table(:captures) { missing.each { |column| add_column column, String } } unless missing.empty?
    end

    def self.new_run_id = "#{Time.now.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(3)}"

    Streamed = Data.define(:outcome, :interrupted)

    # status is succeeded | failed | interrupted. path and capture are nil when a
    # succeeded log was not retained.
    Recorded = Data.define(:capture, :status, :outcome, :path, :error, :started_at, :finished_at)

    # Runs spec with our own stdin (tty or pipe, untouched), streaming its
    # combined stdout/stderr in bounded chunks to path and out. Ctrl-C reaches
    # the child; the parent notes it and reports the child's own outcome. When
    # out goes away (a closed pipe) the file still receives every byte.
    def self.stream(spec, path:, out: $stdout, stdin: $stdin)
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, 'wb') do |file|
        reader, writer = IO.pipe
        pid = begin
          Process.spawn(*spec.spawn_args(in: stdin, out: writer, err: writer))
        rescue SystemCallError
          reader.close
          raise
        ensure
          writer.close
        end
        interrupted = false
        previous = trap('INT') { interrupted = true }
        begin
          chunk = String.new(capacity: 65_536)
          loop do
            reader.readpartial(65_536, chunk)
            file.write(chunk)
            next unless out
            begin
              out.write(chunk)
              out.flush
            rescue Errno::EPIPE, IOError
              out = nil
            end
          end
        rescue EOFError
          nil
        ensure
          reader.close
          _, status = Process.wait2(pid)
          trap('INT', previous)
        end
        outcome = ProcessOutcome.from_status(status)
        Streamed.new(outcome, interrupted || outcome.signal == 'INT')
      end
    end

    # Streams the command into path and records the capture row with its run
    # evidence, even when the command cannot start (exit 127, the error in the
    # log). retain: :failures deletes a succeeded log and records nothing.
    def self.record(spec, path:, name:, run_id: new_run_id, source: 'capture', context: nil, retain: :always,
                    out: $stdout, stdin: $stdin, err: $stderr)
      started = Time.now
      error = nil
      begin
        streamed = stream(spec, path: path, out: out, stdin: stdin)
        outcome = streamed.outcome
      rescue SystemCallError => e
        error = "#{spec.argv.first}: #{e.message}"
        err.puts error
        File.write(path, "#{error}\n")
        outcome = ProcessOutcome.new(exit_code: 127)
      end
      finished = Time.now
      status = streamed&.interrupted ? 'interrupted' : (outcome.success? ? 'succeeded' : 'failed')
      if retain == :failures && status == 'succeeded'
        File.delete(path)
        return Recorded.new(nil, status, outcome, nil, error, started, finished)
      end

      capture = create(name: name, path: path, command: spec.preview, exit_status: outcome.shell_code,
                       exit_signal: outcome.signal, outcome: status, source: source, run_id: run_id,
                       cwd: spec.cwd || Dir.pwd, started_at: started.iso8601(3), finished_at: finished.iso8601(3),
                       task_name: context&.task&.name, context_json: context && JSON.generate(context.provenance))
      Recorded.new(capture, status, outcome, path, error, started, finished)
    end

    # Most-recent-first scope. id is autoincrement, so desc(:id) == chronological reverse.
    def self.recent(limit = nil)
      ds = order(Sequel.desc(:id))
      limit ? ds.limit(limit).all : ds.all
    end

    # Fetch the capture at offset n from the most recent (0 = newest).
    def self.at_offset(n)
      order(Sequel.desc(:id)).offset(n.to_i).first
    end

    def status_glyph
      return "\e[33m!\e[0m" if outcome == 'interrupted'

      case exit_status
      when 0   then "\e[32m✓\e[0m"
      when nil then "\e[33m?\e[0m"
      else          "\e[31m✗\e[0m"
      end
    end

    def display_string(idx)
      cmd = command.to_s
      cmd = cmd[0, 57] + '…' if cmd.length > 60
      format("%4d. %s  %-22s  %s", idx, status_glyph, name, cmd)
    end
  end
end
