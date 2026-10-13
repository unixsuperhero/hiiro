class Hiiro
  # Candidate sources for completing prompts; screens wrap each in a lambda so nothing runs until a token appears.
  module Completions
    module_function

    def projects = Hiiro::Projects.new.all.keys.uniq.sort

    def tags
      names = Hiiro::Tag.select(:name).distinct.map(:name)
      (names + Hiiro::TodoItem.all.flat_map(&:tags_list)).uniq.sort
    end

    def tables = Hiiro::Table.all.map(&:name).uniq.sort

    def tasks = Hiiro::TaskRecord.all_as_list.map(&:name).uniq.sort

    def branches(repo_path)
      return [] unless repo_path && Dir.exist?(repo_path)

      Dir.chdir(repo_path) { Hiiro::Git::Branches.fetch.names }.uniq.sort
    end
  end
end
