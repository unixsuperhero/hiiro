#!/usr/bin/env ruby

module Project
  def self.load(hiiro)
    attach_methods(hiiro)
    add_subcommands(hiiro)
  end

  def self.attach_methods(hiiro)
    hiiro.define_singleton_method(:project_dirs) do
      proj = File.join(Dir.home, 'proj')
      return {} unless Dir.exist?(proj)
      Dir.children(proj)
        .select { |name| File.directory?(File.join(proj, name)) }
        .each_with_object({}) { |name, h| h[name] = File.join(proj, name) }
    end

    hiiro.define_singleton_method(:projects_from_config) do
      path = File.join(Dir.home, '.config', 'hiiro', 'projects.yml')
      return {} unless File.exist?(path)
      require 'yaml'
      YAML.safe_load_file(path) || {}
    end
  end

  def self.add_subcommands(hiiro)
    hiiro.add_subcmd(:project) do |project_name|
      projects = Hiiro::Projects.new
      path     = projects.find(project_name.to_s)

      if path.nil?
        # Fall back to ~/proj root
        name = 'proj'
        path = File.join(Dir.home, 'proj')
        unless Dir.exist?(path)
          puts "Error: #{path.inspect} does not exist"
          exit 1
        end
        puts "changing dir: #{path}"
        Dir.chdir(path)
        hiiro.start_tmux_session(name)
        next
      end

      name = project_name.to_s
      puts "changing dir: #{path}"
      Dir.chdir(path)
      hiiro.start_tmux_session(name)
    end
  end
end
