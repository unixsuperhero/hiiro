#!/usr/bin/env ruby

module Project
  def self.load(hiiro)
    attach_methods(hiiro)
    add_subcommands(hiiro)
  end

  def self.attach_methods(hiiro)
    hiiro.define_singleton_method(:project_dirs) do
      Hiiro::Projects.new.dirs.transform_values { |path| File.expand_path(path) }
    end

    hiiro.define_singleton_method(:projects_from_config) do
      Hiiro::Project.all_as_hash
    end
  end

  def self.add_subcommands(hiiro)
    hiiro.add_subcmd(:project) do |project_name=nil|
      selected = Hiiro::Projects.new.context(project_name, chooser: hiiro.method(:fuzzyfind_from_map)).validate!
      name = selected.project.respond_to?(:name) ? selected.project.name : selected.project
      puts "changing dir: #{selected.start_directory}"
      Dir.chdir(selected.start_directory)
      hiiro.start_herdr_workspace(name, start_directory: selected.start_directory)
    end
  end
end
