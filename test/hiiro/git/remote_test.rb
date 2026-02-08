require "test_helper"

class GitRemoteTest < Minitest::Test
  def test_remote_initialization
    remote = Hiiro::Git::Remote.new(name: "origin")

    assert_equal "origin", remote.name
    assert_nil remote.fetch_url
    assert_nil remote.push_url
  end

  def test_remote_with_urls
    remote = Hiiro::Git::Remote.new(
      name: "origin",
      fetch_url: "git@github.com:user/repo.git",
      push_url: "git@github.com:user/repo.git"
    )

    assert_equal "git@github.com:user/repo.git", remote.fetch_url
    assert_equal "git@github.com:user/repo.git", remote.push_url
  end

  def test_remote_to_s
    remote = Hiiro::Git::Remote.new(name: "upstream")

    assert_equal "upstream", remote.to_s
  end

  def test_remote_to_h
    remote = Hiiro::Git::Remote.new(
      name: "origin",
      fetch_url: "git@github.com:user/repo.git"
    )

    hash = remote.to_h
    assert_equal "origin", hash[:name]
    assert_equal "git@github.com:user/repo.git", hash[:fetch_url]
    refute hash.key?(:push_url)
  end

  def test_remote_from_verbose_line_fetch
    line = "origin\tgit@github.com:user/repo.git (fetch)"
    remote = Hiiro::Git::Remote.from_verbose_line(line)

    assert_equal "origin", remote.name
    assert_equal "git@github.com:user/repo.git", remote.fetch_url
    assert_nil remote.push_url
  end

  def test_remote_from_verbose_line_push
    line = "origin\tgit@github.com:user/repo.git (push)"
    remote = Hiiro::Git::Remote.from_verbose_line(line)

    assert_equal "origin", remote.name
    assert_nil remote.fetch_url
    assert_equal "git@github.com:user/repo.git", remote.push_url
  end

  def test_remote_from_verbose_line_invalid
    line = "not a valid line"
    remote = Hiiro::Git::Remote.from_verbose_line(line)

    assert_nil remote
  end

  def test_remote_origin
    remote = Hiiro::Git::Remote.origin

    assert_equal "origin", remote.name
  end

  def test_remote_url_prefers_fetch_url
    remote = Hiiro::Git::Remote.new(
      name: "origin",
      fetch_url: "https://fetch.url",
      push_url: "https://push.url"
    )

    assert_equal "https://fetch.url", remote.url
  end

  def test_remote_url_falls_back_to_push_url
    remote = Hiiro::Git::Remote.new(
      name: "origin",
      push_url: "https://push.url"
    )

    assert_equal "https://push.url", remote.url
  end
end
