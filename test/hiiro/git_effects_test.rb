require 'test_helper'

class GitEffectsTest < Minitest::Test
  def repository(path)
    FileUtils.mkdir_p(path)
    system('git', 'init', '--quiet', '--initial-branch=main', path) || raise('git init failed')
    File.write(File.join(path, 'tracked'), 'initial')
    system('git', '-C', path, 'add', 'tracked') || raise('git add failed')
    system('git', '-C', path, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
      '-c', 'core.hooksPath=/dev/null', 'commit', '--quiet', '-m', 'fixture') || raise('git commit failed')
  end

  def test_queries_checks_and_checkout_use_supplied_repository_not_process_cwd
    Dir.mktmpdir do |sandbox|
      target = File.join(File.realpath(sandbox), 'target')
      ambient = File.join(File.realpath(sandbox), 'ambient')
      repository(target)
      repository(ambient)
      system('git', '-C', target, 'branch', 'target-only') || raise('git branch failed')
      git = Hiiro::Git.new(nil, target)
      Dir.chdir(ambient) do
        assert_equal target, git.root
        assert git.branch_exists?('target-only')
        refute Hiiro::Git.new(nil, ambient).branch_exists?('target-only')
        assert git.checkout('target-only')
        assert_equal 'target-only', git.current_branch_name
        assert_equal 'main', Hiiro::Git.new(nil, ambient).current_branch_name
      end
    end
  end
end
