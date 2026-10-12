require 'test_helper'

class PaneHomeTest < Minitest::Test
  def setup
    Hiiro::PaneHome.where(name: %w[home-test other-home-test]).delete
  end

  def teardown
    Hiiro::PaneHome.where(name: %w[home-test other-home-test]).delete
  end

  def test_targeted_update_merges_current_payload_and_retains_id
    original = Hiiro::PaneHome.set('home-test', session: 'legacy', path: '/keep', custom: { 'color' => 'blue' })
    stale = Hiiro::PaneHome.all_as_hash
    Hiiro::PaneHome.set('home-test', path: '/new', concurrent: false)
    other = Hiiro::PaneHome.set('other-home-test', workspace: 'other')
    Hiiro::PaneHome.set('home-test', workspace: 'current')
    stale.delete('other-home-test')
    saved = Hiiro::PaneHome.find_by_name('home-test')
    assert_equal original.id, saved.id
    assert_equal({ 'session' => 'legacy', 'path' => '/new', 'custom' => { 'color' => 'blue' }, 'concurrent' => false, 'workspace' => 'current' }, saved.data)
    assert_equal [other.id, { 'workspace' => 'other' }], [Hiiro::PaneHome.find_by_name('other-home-test').id, Hiiro::PaneHome.find_by_name('other-home-test').data]
  end

  def test_explicit_nil_clears_only_supplied_field_and_removal_is_exact
    Hiiro::PaneHome.set('home-test', workspace: 'work', path: '/old', session: 'legacy')
    other = Hiiro::PaneHome.set('other-home-test', workspace: 'other')
    Hiiro::PaneHome.set('home-test', path: nil)
    assert_equal({ 'workspace' => 'work', 'path' => nil, 'session' => 'legacy' }, Hiiro::PaneHome.find_by_name('home-test').data)
    assert_nil Hiiro::PaneHome.remove('home')
    assert_equal({ 'workspace' => 'work', 'path' => nil, 'session' => 'legacy' }, Hiiro::PaneHome.find_by_name('home-test').data)
    Hiiro::PaneHome.remove('home-test')
    assert_nil Hiiro::PaneHome.find_by_name('home-test')
    assert_equal [other.id, { 'workspace' => 'other' }], [Hiiro::PaneHome.find_by_name('other-home-test').id, Hiiro::PaneHome.find_by_name('other-home-test').data]
  end
end
