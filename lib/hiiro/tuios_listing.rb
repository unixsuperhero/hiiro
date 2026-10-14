require 'json'

class Hiiro
  # Every tuios window on this machine, read through the tuios command line:
  # `ls --json` for sessions and windows, `list-windows -s S --json` per local
  # session for cwd and layout, `list-attention --json` for the header counts,
  # and `ls --all-hosts --json` for one summary row per remote session.
  class TuiosListing
    Window = Struct.new(:id, :title, :session, :workspace, :index, :state, :harness, :message, :cwd, :cmd, :focused, :minimized, :host, keyword_init: true) do
      def kind = :window
      def key = id
      def label = host == 'local' ? session : "#{host}:#{session}"
    end

    Remote = Struct.new(:host, :session, :windows, :state, keyword_init: true) do
      def kind = :session
      def key = "#{host}:#{session}"
      def label = key
    end

    Session = Struct.new(:name, :id, :attached, :dir, :branch, :host, keyword_init: true)

    def self.load(runner: nil, hosts: false)
      new(runner: runner || Hiiro::Tuios.new.method(:capture), hosts:).reload
    end

    attr_reader :runner, :windows, :sessions, :attention
    attr_accessor :hosts

    def initialize(runner:, hosts: false)
      @runner = runner
      @hosts = hosts
      @windows = []
      @sessions = []
      @attention = {}
    end

    def reload
      data = JSON.parse(runner.call('ls', '--json'))
      @sessions = data.map { |session| session_from(session, 'local') }
      local = data.flat_map { |session| local_windows(session) }.sort_by { |w| [w.host, w.session, w.workspace, w.index] }
      remote = hosts ? remote_rows : []
      @windows = local + remote
      @attention = load_attention
      self
    end

    private

    def session_from(session, host)
      Session.new(name: session['name'], id: session['id'], attached: session['attached'] == true,
                  dir: session['dir'], branch: session['branch'], host:)
    end

    def local_windows(session)
      listed = session['windows'] || []
      return [] if listed.empty?

      details = window_details(session['name'])
      listed.map do |w|
        detail = details[w['id']] || {}
        Window.new(
          id: w['id'], title: w['title'].to_s, session: session['name'], workspace: w['workspace'].to_i,
          index: detail['index'].to_i, state: w['agent_state'] || 'none', harness: w['agent_harness'],
          message: w['agent_message'], cwd: detail['cwd'], cmd: detail['running_cmdline'] || w['foreground_cmd'],
          focused: detail['focused'] == true, minimized: detail['minimized'] == true, host: 'local',
        )
      end
    end

    def window_details(name)
      out = JSON.parse(runner.call('list-windows', '-s', name, '--json'))
      (out['windows'] || []).to_h { |w| [w['window_id'], w] }
    rescue Hiiro::Error
      {}
    end

    def remote_rows
      data = JSON.parse(runner.call('ls', '--all-hosts', '--json'))
      rows = (data['hosts'] || []).reject { |h| h['host'] == 'local' }.flat_map do |h|
        (h['sessions'] || []).map do |s|
          @sessions << session_from(s, h['host'])
          Remote.new(host: h['host'], session: s['name'], windows: s['window_count'].to_i, state: s['agent_state'])
        end
      end
      rows.sort_by { |row| [row.host, row.session] }
    end

    def load_attention
      counts = JSON.parse(runner.call('list-attention', '--json'))['counts'] || {}
      counts.select { |_, count| count.to_i.positive? }
    rescue StandardError
      {}
    end
  end
end
