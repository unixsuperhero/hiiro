require 'json'
require 'socket'
require 'timeout'

class Hiiro
  class Herdr
    class Collection
      include Enumerable

      def initialize(items)
        @items = items
      end

      def each(&block) = @items.each(&block)
      def empty? = @items.empty?
      def size = @items.size
      alias count size
      alias length size

      def names = @items.map(&:name)

      def name_map
        @items.each_with_object({}) { |item, map| map[item.to_s] = item.id }
      end
    end

    class Workspace
      attr_reader :client, :id, :number, :label, :pane_count, :tab_count,
                  :active_tab_id, :agent_status, :worktree

      def initialize(data, client: Herdr.client)
        @client = client
        @id = data['workspace_id']
        @number = data['number'].to_i
        @label = data['label'].to_s
        @focused = data['focused'] == true
        @pane_count = data['pane_count'].to_i
        @tab_count = data['tab_count'].to_i
        @active_tab_id = data['active_tab_id']
        @agent_status = data['agent_status']
        @worktree = data['worktree']
      end

      alias name label
      alias windows tab_count

      def focused? = @focused
      alias attached? focused?

      def ==(other)
        other.is_a?(Workspace) && name == other.name
      end

      def path
        worktree&.fetch('checkout_path', nil)
      end

      def close = client.close_workspace(id)
      alias kill close

      def rename(new_label) = client.rename_workspace(id, new_label)
      def select = client.focus_workspace(id)
      alias attach select

      def to_h
        {
          id: id,
          number: number,
          label: label,
          focused: focused?,
          pane_count: pane_count,
          tab_count: tab_count,
          active_tab_id: active_tab_id,
          agent_status: agent_status,
          worktree: worktree,
        }.compact
      end

      def to_s
        "#{id} #{label} [#{tab_count} tabs, #{pane_count} panes]#{focused? ? ' *' : ''}"
      end
    end

    class Workspaces < Collection
      def find_by_id(id) = @items.find { |workspace| workspace.id == id }
      def find_by_name(name) = @items.find { |workspace| workspace.name == name }
      def focused = self.class.new(@items.select(&:focused?))
    end

    class Tab
      attr_reader :client, :id, :workspace_id, :number, :label, :pane_count,
                  :agent_status

      def initialize(data, client: Herdr.client)
        @client = client
        @id = data['tab_id']
        @workspace_id = data['workspace_id']
        @number = data['number'].to_i
        @label = data['label'].to_s
        @focused = data['focused'] == true
        @pane_count = data['pane_count'].to_i
        @agent_status = data['agent_status']
      end

      alias name label
      alias index number
      alias panes pane_count
      alias target id

      def focused? = @focused
      alias active? focused?

      def close = client.close_tab(id)
      alias kill close

      def rename(new_label) = client.rename_tab(id, new_label)
      def select = client.focus_tab(id)

      def to_h
        {
          id: id,
          workspace_id: workspace_id,
          number: number,
          label: label,
          focused: focused?,
          pane_count: pane_count,
          agent_status: agent_status,
        }.compact
      end

      def to_s
        "#{id} #{label} [#{pane_count} panes]#{focused? ? ' *' : ''}"
      end
    end

    class Tabs < Collection
      def find_by_id(id) = @items.find { |tab| tab.id == id }
      def find_by_name(name) = @items.find { |tab| tab.name == name }
      def find_by_index(index) = @items.find { |tab| tab.index == index.to_i }
      def in_workspace(workspace_id) = self.class.new(@items.select { |tab| tab.workspace_id == workspace_id })
      def focused = self.class.new(@items.select(&:focused?))
      alias active focused
    end

    class Pane
      attr_reader :client, :id, :terminal_id, :workspace_id, :tab_id, :cwd,
                  :foreground_cwd, :label, :agent, :title, :agent_status,
                  :width, :height

      def initialize(data, client: Herdr.client, rect: nil)
        @client = client
        @id = data['pane_id']
        @terminal_id = data['terminal_id']
        @workspace_id = data['workspace_id']
        @tab_id = data['tab_id']
        @focused = data['focused'] == true
        @cwd = data['cwd']
        @foreground_cwd = data['foreground_cwd']
        @label = data['label']
        @agent = data['agent']
        @title = data['title'] || data['terminal_title_stripped'] || data['terminal_title']
        @agent_status = data['agent_status']
        @width = rect&.fetch('width', 0).to_i
        @height = rect&.fetch('height', 0).to_i
      end

      alias target id
      alias path foreground_cwd

      def name = label || title || agent || id
      def command = agent || title
      def focused? = @focused
      alias active? focused?

      def close = client.close_pane(id)
      alias kill close

      def select = client.focus_pane(id)
      def swap_with(other_id) = client.swap_pane(id, other_id)
      def move_to(other_id) = client.join_pane(id, other_id)
      def break_out = client.break_pane(id)
      def resize(direction:, amount: nil) = client.resize_pane(target: id, direction:, amount:)
      def zoom = client.zoom_pane(id)
      def capture = client.read_pane(id)

      def to_h
        {
          id: id,
          terminal_id: terminal_id,
          workspace_id: workspace_id,
          tab_id: tab_id,
          focused: focused?,
          cwd: cwd,
          foreground_cwd: foreground_cwd,
          label: label,
          agent: agent,
          title: title,
          agent_status: agent_status,
          width: width,
          height: height,
        }.compact
      end

      def to_s
        "#{id} #{name} [#{workspace_id} / #{tab_id}]#{focused? ? ' *' : ''}"
      end

      # `herdr pane process-info` for this pane, fetched once.
      def process_info
        @process_info ||= client.process_info(id)
      end

      # Command line of the foreground process group leader, or nil at a shell prompt.
      def foreground_command
        procs = process_info['foreground_processes'] || []
        leader = procs.find { |proc| proc['pid'] == process_info['foreground_process_group_id'] } || procs.last
        return nil if leader.nil? || leader['pid'] == process_info['shell_pid']
        leader['cmdline']
      end
    end

    class Panes < Collection
      def find_by_id(id) = @items.find { |pane| pane.id == id }
      def in_workspace(workspace_id) = self.class.new(@items.select { |pane| pane.workspace_id == workspace_id })
      def in_tab(tab_id) = self.class.new(@items.select { |pane| pane.tab_id == tab_id })
      def focused = self.class.new(@items.select(&:focused?))
      def ids = @items.map(&:id)
    end

    class << self
      def client!(hiiro = nil)
        @client = new(hiiro)
      end

      def client(hiiro = nil)
        return @client if @client && @client.hiiro == hiiro

        hiiro ? client!(hiiro) : new
      end

      def open_workspace(name, **opts)
        client.open_workspace(name, **opts)
      end

      alias open_session open_workspace

      def add_resolvers(hiiro)
        hiiro.add_resolver(:pane,
          -> { hiiro.fuzzyfind_from_map(hiiro.herdr_client.panes.name_map) }
        ) { |ref| resolve_item_id(hiiro.herdr_client.panes, ref) }

        hiiro.add_resolver(:window,
          -> { hiiro.fuzzyfind_from_map(hiiro.herdr_client.tabs.name_map) }
        ) { |ref| resolve_item_id(hiiro.herdr_client.tabs, ref) }

        hiiro.add_resolver(:session,
          -> { hiiro.fuzzyfind_from_map(hiiro.herdr_client.workspaces.name_map) }
        ) { |ref| resolve_item_id(hiiro.herdr_client.workspaces, ref) }
      end

      private

      def resolve_item_id(items, ref)
        return ref if items.any? { |item| item.id == ref }

        matches = items.select { |item| item.name.start_with?(ref.to_s) }
        matches.one? ? matches.first.id : ref
      end
    end

    attr_reader :hiiro

    def initialize(hiiro = nil, executor: Hiiro::Effects::Executor.new)
      @hiiro = hiiro
      @executor = executor
    end

    def in_herdr? = ENV['HERDR_ENV'] == '1'
    def server_running? = @executor.check('herdr', 'status', 'server')

    def workspaces
      rows = capture_result('workspace', 'list').fetch('workspaces', [])
      Workspaces.new(rows.map { |row| Workspace.new(row, client: self) })
    end

    alias sessions workspaces

    def tabs(workspace: nil, all: false)
      workspace_id = workspace_id_for(workspace)
      args = ['tab', 'list']
      args += ['--workspace', workspace_id] if workspace_id && !all
      rows = capture_result(*args).fetch('tabs', [])
      Tabs.new(rows.map { |row| Tab.new(row, client: self) })
    end

    def panes(workspace: nil, all: false, **)
      workspace_id = workspace_id_for(workspace)
      args = ['pane', 'list']
      args += ['--workspace', workspace_id] if workspace_id && !all
      rows = capture_result(*args).fetch('panes', [])
      Panes.new(rows.map { |row| Pane.new(row, client: self) })
    end

    def current_workspace
      id = ENV['HERDR_WORKSPACE_ID']
      id ? get_workspace(id) : workspaces.find(&:focused?)
    end

    alias current_session current_workspace

    def current_tab
      id = ENV['HERDR_TAB_ID']
      id ? get_tab(id) : tabs.find(&:focused?)
    end

    alias current_window current_tab

    def current_pane
      args = ['pane', 'current']
      args << '--current' if ENV['HERDR_PANE_ID']
      row = capture_result(*args)['pane']
      row && Pane.new(row, client: self, rect: pane_rect(row['pane_id']))
    end

    def get_workspace(id)
      row = capture_result('workspace', 'get', id)['workspace']
      row && Workspace.new(row, client: self)
    end

    def get_tab(id)
      row = capture_result('tab', 'get', id)['tab']
      row && Tab.new(row, client: self)
    end

    def process_info(pane_id)
      capture_result('pane', 'process-info', '--pane', pane_id).fetch('process_info', {})
    end

    def get_pane(id)
      row = capture_result('pane', 'get', id)['pane']
      row && Pane.new(row, client: self, rect: pane_rect(id))
    end

    def find_workspace(ref)
      return nil if ref.nil?

      normalized = ref.to_s.tr('.', '_')
      workspaces.find { |workspace| workspace.id == ref || workspace.name == normalized } ||
        begin
          matches = workspaces.select { |workspace| workspace.name.start_with?(normalized) }
          matches.one? ? matches.first : nil
        end
    end

    def workspace_exists?(ref) = !find_workspace(ref).nil?

    alias find_session find_workspace
    alias session_exists? workspace_exists?

    def open_workspace(name, start_directory: nil, **)
      workspace = find_workspace(name)
      return focus_workspace(workspace.id) if workspace

      new_workspace(name, start_directory:, focus: true)
    end

    def new_workspace(name = nil, start_directory: nil, focus: true, tab_name: nil, **)
      args = ['workspace', 'create']
      args += ['--label', name.to_s.tr('.', '_')] if name
      args += ['--cwd', start_directory] if start_directory
      args << (focus ? '--focus' : '--no-focus')
      result = capture_result(*args)
      rename_tab(result.dig('tab', 'tab_id'), tab_name) if tab_name && result.dig('tab', 'tab_id')
      row = result['workspace']
      row && Workspace.new(row, client: self)
    end

    def new_session(name = nil, detached: false, window_name: nil, **opts)
      new_workspace(name, focus: !detached, tab_name: window_name, **opts)
    end

    def close_workspace(ref)
      id = find_workspace(ref)&.id || ref
      @executor.run('herdr', 'workspace', 'close', id)
    end

    alias kill_session close_workspace

    def focus_workspace(ref)
      id = find_workspace(ref)&.id || ref
      @executor.run('herdr', 'workspace', 'focus', id)
    end

    alias attach_session focus_workspace
    alias switch_client focus_workspace

    def rename_workspace(ref, label)
      id = find_workspace(ref)&.id || ref
      @executor.run('herdr', 'workspace', 'rename', id, label)
    end

    alias rename_session rename_workspace

    def open_session(name, **opts)
      open_workspace(name, **opts)
    end

    def new_tab(name: nil, workspace: nil, start_directory: nil, command: nil, focus: true)
      args = ['tab', 'create']
      workspace_id = workspace_id_for(workspace)
      args += ['--workspace', workspace_id] if workspace_id
      args += ['--label', name] if name
      args += ['--cwd', start_directory] if start_directory
      args << (focus ? '--focus' : '--no-focus')
      result = capture_result(*args)
      pane_id = result.dig('root_pane', 'pane_id')
      run_in_pane(pane_id, command) if pane_id && command
      result
    end

    def new_window(name: nil, target: nil, **opts)
      new_tab(name: name, workspace: target, **opts)
    end

    def close_tab(ref)
      id = find_tab(ref)&.id || ref
      @executor.run('herdr', 'tab', 'close', id)
    end

    alias kill_window close_tab

    def focus_tab(ref)
      id = find_tab(ref)&.id || ref
      @executor.run('herdr', 'tab', 'focus', id)
    end

    alias select_window focus_tab

    def rename_tab(ref, label)
      id = find_tab(ref)&.id || ref
      @executor.run('herdr', 'tab', 'rename', id, label)
    end

    alias rename_window rename_tab

    def find_tab(ref)
      return nil if ref.nil?

      tabs.find { |tab| tab.id == ref || tab.name == ref } ||
        begin
          matches = tabs.select { |tab| tab.name.start_with?(ref.to_s) }
          matches.one? ? matches.first : nil
        end
    end

    def next_tab
      focus_relative_tab(1)
    end

    alias next_window next_tab

    def previous_tab
      focus_relative_tab(-1)
    end

    alias previous_window previous_tab

    def last_tab
      current = current_tab
      candidates = tabs(workspace: current&.workspace_id).to_a
      focus_tab(candidates.last.id) if candidates.any?
    end

    alias last_window last_tab

    def windows(session: nil, all: false)
      tabs(workspace: session, all: all)
    end

    def split_pane(direction:, target: nil, start_directory: nil, ratio: nil, command: nil, focus: true)
      args = ['pane', 'split']
      args += target ? ['--pane', target] : ['--current']
      args += ['--direction', direction.to_s]
      args += ['--cwd', start_directory] if start_directory
      args += ['--ratio', normalize_ratio(ratio).to_s] if ratio
      args << (focus ? '--focus' : '--no-focus')
      row = capture_result(*args)['pane']
      run_in_pane(row['pane_id'], command) if row && command
      row && Pane.new(row, client: self)
    end

    def hsplit_window(size: nil, **opts) = split_pane(direction: :down, ratio: size, **opts)
    def vsplit_window(size: nil, **opts) = split_pane(direction: :right, ratio: size, **opts)

    def split_window(horizontal: false, target: nil, start_directory: nil, size: nil, command: nil, **)
      split_pane(
        direction: horizontal ? :right : :down,
        target:,
        start_directory:,
        ratio: size,
        command:
      )
    end

    def close_pane(ref) = @executor.run('herdr', 'pane', 'close', ref)
    alias kill_pane close_pane

    def focus_pane(ref)
      status = @executor.capture('herdr', 'status', 'server')
      socket_path = status.lines.find { |line| line.start_with?('socket: ') }&.delete_prefix('socket: ')&.strip
      return false unless socket_path

      request = { id: 'hiiro:pane:focus', method: 'pane.focus', params: { pane_id: ref } }
      Timeout.timeout(5) do
        UNIXSocket.open(socket_path) do |socket|
          socket.puts(JSON.generate(request))
          response = JSON.parse(socket.gets || '{}')
          response.dig('result', 'pane', 'focused') == true
        end
      end
    rescue SystemCallError, IOError, JSON::ParserError, Timeout::Error
      false
    end
    alias select_pane focus_pane

    def zoom_pane(ref = nil)
      args = ['pane', 'zoom']
      args += ref ? [ref] : ['--current']
      @executor.run('herdr', *args, '--toggle')
    end

    def swap_pane(src, dst)
      @executor.run('herdr', 'pane', 'swap', '--source-pane', src, '--target-pane', dst)
    end

    def swap_current_pane(direction = :left, **)
      direction = :left unless %i[left right up down].include?(direction.to_sym)
      @executor.run('herdr', 'pane', 'swap', '--current', '--direction', direction.to_s)
    end

    def break_pane(src: nil, **)
      pane_id = src || ENV['HERDR_PANE_ID']
      return false unless pane_id

      @executor.run('herdr', 'pane', 'move', pane_id, '--new-tab', '--focus')
    end

    def join_pane(src, dst, horizontal: false)
      destination = get_pane(dst)
      return false unless destination

      @executor.run(
        'herdr', 'pane', 'move', src,
        '--tab', destination.tab_id,
        '--target-pane', dst,
        '--split', horizontal ? 'right' : 'down',
        '--focus'
      )
    end

    def resize_pane(target: nil, direction: nil, amount: nil, zoom: false, **)
      return zoom_pane(target) if zoom
      return false unless direction

      args = ['pane', 'resize', '--direction', direction.to_s]
      args += target ? ['--pane', target] : ['--current']
      args += ['--amount', amount.to_s] if amount
      @executor.run('herdr', *args)
    end

    def read_pane(target = nil, source: 'recent-unwrapped', lines: nil)
      pane_id = target || ENV['HERDR_PANE_ID']
      return nil unless pane_id

      args = ['pane', 'read', pane_id, '--source', source]
      args += ['--lines', lines.to_s] if lines
      @executor.capture('herdr', *args)
    end
    alias capture_pane read_pane

    def run_in_pane(pane_id, command)
      @executor.run('herdr', 'pane', 'run', pane_id, command)
    end

    def send_text(pane_id, text)
      @executor.run('herdr', 'pane', 'send-text', pane_id, text)
    end

    def send_keys(pane_id, *keys)
      @executor.run('herdr', 'pane', 'send-keys', pane_id, *keys)
    end

    def notify(title, body: nil, sound: nil)
      args = ['notification', 'show', title]
      args += ['--body', body] if body
      args += ['--sound', sound.to_s] if sound
      @executor.run('herdr', *args)
    end

    private

    def capture_result(*args)
      output = @executor.capture('herdr', *args).to_s.strip
      return {} if output.empty?

      JSON.parse(output).fetch('result', {})
    rescue JSON::ParserError
      {}
    end

    def workspace_id_for(ref)
      return nil if ref.nil?
      return ref.id if ref.respond_to?(:id)

      find_workspace(ref)&.id || ref
    end

    def pane_rect(pane_id)
      result = capture_result('pane', 'layout', '--pane', pane_id)
      result.dig('layout', 'panes')&.find { |pane| pane['pane_id'] == pane_id }&.fetch('rect', nil)
    end

    def focus_relative_tab(offset)
      current = current_tab
      candidates = tabs(workspace: current&.workspace_id).to_a
      return false if candidates.empty?

      index = candidates.index { |tab| tab.id == current&.id } || 0
      focus_tab(candidates[(index + offset) % candidates.length].id)
    end

    def normalize_ratio(value)
      string = value.to_s
      ratio = string.end_with?('%') ? string.to_f / 100.0 : string.to_f
      ratio > 1 ? ratio / 100.0 : ratio
    end
  end
end
