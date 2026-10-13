require 'shellwords'

class Hiiro
  # One registration for the bins that act on a fixed directory: h home,
  # h dotfiles, h vim, and h plugin. Each profile names its root and the
  # actions it offers; the actions are shared methods, so a verb that two
  # profiles offer behaves the same in both. Actions that run in the root
  # resolve it through TaskLocation (root_source is the profile name; there
  # is never a task) and run the native tool there.
  #
  #   DirectoryProfile.named('vim').root     # => "/Users/me/.config/nvim"
  #   DirectoryProfile.named('vim').register(hiiro, source: __FILE__)
  class DirectoryProfile
    # name => { root:, actions: { [subcommand, *aliases] => action method } }
    PROFILES = {
      'home' => {
        root: '~',
        actions: {
          %i[edit] => :edit_source, %i[path] => :print_path, %i[abspath] => :print_location, %i[open] => :open_root, %i[cd] => :cd_pane,
          %i[sh] => :shell, %i[skf] => :skf, %i[rg] => :rg, %i[rgall] => :rgall, %i[ebin] => :edit_bin_matches,
        },
      },
      'dotfiles' => {
        root: '~/proj/home',
        actions: {
          %i[edit] => :edit_source, %i[path] => :print_path, %i[skf] => :skf, %i[rg] => :rg, %i[rgall] => :rgall,
          %i[ebin] => :edit_arguments,
        },
      },
      'vim' => {
        root: '~/.config/nvim',
        actions: {
          %i[edit] => :edit_source, %i[path] => :print_path, %i[init config] => :edit_init, %i[skf] => :skf,
          %i[rg] => :rg, %i[rgall] => :rgall, %i[session tmux] => :tmux_session,
        },
      },
      'plugin' => {
        root: '~/.config/hiiro/plugins',
        actions: { %i[path] => :print_path, %i[ls] => :list_files, %i[edit] => :edit_plugins, %i[rg] => :rg, %i[rgall] => :rgall },
      },
    }.freeze

    TMUX_SESSION = 'vim'

    def self.named(name)
      spec = PROFILES.fetch(name.to_s) { raise Error, "Unknown directory profile: #{name}" }
      new(name: name.to_s, root: File.expand_path(spec[:root]), actions: spec[:actions])
    end

    attr_reader :name, :root, :actions

    def initialize(name:, root:, actions:)
      @name = name
      @root = root
      @actions = actions
    end

    # The root as resolved context; raises Hiiro::Error when it is missing.
    def location
      TaskLocation.for(nil, root: root, root_source: name.to_sym, terminal: Herdr::Location.from_env).validate!
    end

    def files = Dir.glob(File.join(root, '**/*'))

    # Adds every action of this profile to hiiro. source is the bin file
    # that `edit` with no arguments opens.
    def register(hiiro, source:)
      profile = self
      actions.each do |names, action|
        hiiro.add_subcmd(*names) { |*args| profile.public_send(action, hiiro, source, *args) }
      end
      hiiro
    end

    def edit_source(hiiro, source, *) = hiiro.edit_files(source)

    # The configured root, printed as is and without a newline, whether or not it exists.
    def print_path(_hiiro, _source, *) = print(root)

    # The resolved root (real path; it must exist), without a newline.
    def print_location(*) = print(location.start_directory)

    def open_root(hiiro, _source, *) = hiiro.open_default(location.start_directory)

    def cd_pane(*)
      selected = location
      terminal = selected.terminal
      raise Error, 'Not running inside a Herdr pane' unless terminal.pane_id

      client = Herdr.client
      terminal.validate!(client)
      client.run_in_pane(terminal.pane_id, "cd #{selected.start_directory.shellescape}")
    end

    def shell(_hiiro, _source, *native_args)
      Dir.chdir(location.start_directory)
      native_args.empty? ? exec(ENV['SHELL'] || 'zsh') : exec(*native_args)
    end

    def skf(_hiiro, _source, *args) = run_in_root('skf', *args)
    def rg(_hiiro, _source, *args) = run_in_root('rg', '-S', *args)
    def rgall(_hiiro, _source, *args) = run_in_root('rg', '-S', '--no-ignore-vcs', *args)

    # h home ebin: files in ROOT/bin matching each pattern (`*PATTERN*`
    # unless the pattern already ends in `*`).
    def edit_bin_matches(_hiiro, _source, *patterns)
      selected = location.with_directory(File.join(root, 'bin'), source: :override).validate!
      Dir.chdir(selected.start_directory)
      files = patterns.flat_map { |pattern| Dir.glob(pattern.end_with?('*') ? pattern : "*#{pattern}*") }
      system(editor, *files)
    end

    # h dotfiles ebin: the arguments as given, from the current directory.
    def edit_arguments(_hiiro, _source, *paths) = system(editor, *paths)

    def edit_init(*)
      Dir.chdir(location.start_directory)
      system(editor, 'init.lua')
    end

    # h plugin edit: no arguments edits the bin; otherwise every plugin file
    # whose basename starts with one of the arguments.
    def edit_plugins(hiiro, source, *prefixes)
      return hiiro.edit_files(source) if prefixes.empty?

      matcher = Matcher.new(files) { |file| File.basename(file) }
      plugins = prefixes.flat_map { |prefix| matcher.by_prefix(prefix).matches.map(&:item) }.uniq
      return puts("No matching plugins found for: #{prefixes.map(&:inspect).join(' ')}") if plugins.empty?

      hiiro.edit_files(*plugins)
    end

    def list_files(*) = puts(files)

    # The optional tmux adapter: a `vim` session started in the root, then
    # switched to (inside tmux) or attached.
    def tmux_session(*)
      raise Error, 'tmux not found' unless Bins.which('tmux')

      directory = location.start_directory
      system('tmux', 'new-session', '-d', '-s', TMUX_SESSION, '-c', directory) unless system('tmux', 'has-session', '-t', TMUX_SESSION, err: File::NULL)
      return system('tmux', 'switch-client', '-t', TMUX_SESSION) if ENV['TMUX']
      return puts("Can't attach to tmux inside a vim terminal") if ENV['NVIM']

      system('tmux', 'attach-session', '-t', TMUX_SESSION)
    end

    private

    def editor = ENV.fetch('EDITOR', 'nvim')

    def run_in_root(*argv)
      Dir.chdir(location.start_directory)
      system(*argv)
    end
  end
end
