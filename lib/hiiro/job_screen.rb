class Hiiro
  # `h schedule ui` and `h loop ui`: recorded job outcomes, newest first. The
  # rows are re-read in the background; the query, selection, and scroll stay.
  class JobScreen < Tui::Screen
    Row = Struct.new(:outcome) do
      def key = outcome.run_id

      def to_s
        finished = outcome.finished_at.to_s.sub('T', ' ')[0, 19]
        format('%-19s  %-16s  %-16s  %s', finished, outcome.definition, outcome.status_text, outcome.detail)
      end
    end

    key 'r', :reload

    def self.rows(definition: nil) = JobOutcome.recent(definition: definition).map { |outcome| Row.new(outcome) }

    def initialize(definition: nil, interval: 5, loader: nil)
      @definition = definition
      @interval = interval
      @loader = loader || -> { self.class.rows(definition: definition) }
      super(items: @loader.call, empty_message: 'No recorded outcomes.')
    end

    def refresh_interval = @interval

    def refresh!
      replace_items(@loader.call, key: :key.to_proc)
    end

    def header_lines
      ["job outcomes#{@definition ? " #{@definition}*" : ''}  #{items.length} rows  r reload  / search  q quit"]
    end

    def detail_lines(row)
      outcome = row.outcome
      lines = [
        "run       #{outcome.run_id}",
        "schedule  #{outcome.definition}",
        "occurs    #{outcome.occurrence}",
        "outcome   #{outcome.status_text}",
        "started   #{outcome.started_at}",
        "finished  #{outcome.finished_at}",
        "detail    #{outcome.detail}",
      ]
      lines << "log       #{outcome.log_path}" if outcome.log_path
      outcome.artifacts.each { |artifact| lines << "artifact  #{artifact['path']} (#{artifact['bytes']} bytes)" }
      lines << "notified  #{outcome.notification}" if outcome.notification
      if outcome.log_path && File.file?(outcome.log_path)
        lines << '--- log tail ---'
        lines.concat(File.readlines(outcome.log_path, chomp: true).last(8))
      end
      lines
    end

    private

    def reload
      refresh!
      self.message = 'reloaded'
    end
  end
end
