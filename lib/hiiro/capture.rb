require 'sequel'
require 'fileutils'
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

    # Runs spec with our own stdin (tty or pipe, untouched), streaming its
    # combined stdout/stderr in bounded chunks to out and to path. Returns the
    # ProcessOutcome; Ctrl-C goes to the child, whose death is what we report.
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
        previous = trap('INT') {}
        begin
          chunk = String.new(capacity: 65_536)
          loop do
            reader.readpartial(65_536, chunk)
            out.write(chunk)
            out.flush
            file.write(chunk)
          end
        rescue EOFError
          nil
        ensure
          reader.close
          _, status = Process.wait2(pid)
          trap('INT', previous)
        end
        ProcessOutcome.from_status(status)
      end
    end

    # Streams the command into path and records the capture row, even when the
    # command cannot start. Returns [capture, outcome].
    def self.record(spec, path:, name:, out: $stdout, stdin: $stdin, err: $stderr)
      outcome = nil
      begin
        outcome = stream(spec, path: path, out: out, stdin: stdin)
      rescue SystemCallError => e
        err.puts "#{spec.argv.first}: #{e.message}"
        outcome = ProcessOutcome.new(exit_code: 127)
      ensure
        capture = create(name: name, path: path, command: spec.preview, exit_status: outcome&.shell_code)
        err.puts "\n[capture saved: #{path} (#{outcome || 'interrupted'})]"
      end
      [capture, outcome]
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
