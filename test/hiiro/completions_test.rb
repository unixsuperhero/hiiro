require "test_helper"
require "open3"
require "tmpdir"

class CompletionsTest < Minitest::Test
  GIT_ENV = {
    "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_NOSYSTEM" => "1",
    "GIT_AUTHOR_NAME" => "t", "GIT_AUTHOR_EMAIL" => "t@t", "GIT_COMMITTER_NAME" => "t", "GIT_COMMITTER_EMAIL" => "t@t",
  }.freeze

  def setup
    clear_rows
    Hiiro::TaskRecord.create(name: "alpha")
    Hiiro::TodoItem.create(text: "do it", task_name: "alpha", status: "not_started", tags: "a, b", created_at: "2026-10-13")
    Hiiro::Tag.create(name: "c", taggable_type: "RegistryEntry", taggable_id: "1")
    Hiiro::Table.named("link").add("gh", value: "github.com")
  end

  def teardown = clear_rows

  def clear_rows
    [Hiiro::TodoItem, Hiiro::Tag, Hiiro::RegistryEntry, Hiiro::TaskRecord].each { |model| model.dataset.delete }
  end

  def git(dir, *args)
    out, err, status = Open3.capture3(GIT_ENV, "git", "-C", dir, *args)
    raise "git #{args.join(' ')} failed: #{err}" unless status.success?

    out
  end

  def test_tasks_tags_and_tables
    assert_equal %w[alpha], Hiiro::Completions.tasks
    assert_equal %w[a b c], Hiiro::Completions.tags
    assert_equal %w[link], Hiiro::Completions.tables
  end

  def test_projects_returns_an_array
    assert_kind_of Array, Hiiro::Completions.projects
  end

  def test_branches_of_a_repo_and_of_a_missing_path
    Dir.mktmpdir("completions") do |dir|
      git(dir, "init", "-q")
      git(dir, "commit", "-q", "--allow-empty", "-m", "one")
      branch = git(dir, "symbolic-ref", "--short", "HEAD").strip

      assert_equal [branch], Hiiro::Completions.branches(dir)
    end
    assert_equal [], Hiiro::Completions.branches("/nowhere/at/all")
  end
end
