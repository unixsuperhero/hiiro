#!/usr/bin/env ruby

module Project
  def self.load(hiiro)
    add_subcommands(hiiro)
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
