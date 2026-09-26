require "test_helper"

class HerdrLocationTest < Minitest::Test
  class FakeClient
    attr_reader :requests
    def initialize(response) = (@response, @requests = response, [])
    def new_tab(**request)
      @requests << request
      @response
    end
  end

  RESPONSE = {
    'tab' => { 'tab_id' => 'w1:t2', 'workspace_id' => 'w1' },
    'root_pane' => { 'pane_id' => 'w1:p2', 'workspace_id' => 'w1', 'tab_id' => 'w1:t2' },
  }.freeze

  def test_tab_creation_retains_request_and_answers
    client = FakeClient.new(RESPONSE)
    created = Hiiro::Herdr::TabCreation.create(client, name: 'x', workspace: 'w1', focus: false)

    assert_equal [{ name: 'x', workspace: 'w1', focus: false }], client.requests
    assert_equal 'w1:t2', created.tab_id
    assert_equal 'w1:p2', created.pane_id
    assert created.created?
    assert created.complete?
    assert_equal [], created.errors
    assert_equal 'w1:t2', created.tab.id
    assert_equal 'w1:p2', created.root_pane.id
    assert_equal 'w1', created.location.workspace_id
    assert_equal 'w9', created.location(workspace_id: 'w9').workspace_id
  end

  def test_tab_creation_incomplete_responses
    no_pane = Hiiro::Herdr::TabCreation.new(request: {}, response: { 'tab' => { 'tab_id' => 'w1:t2' } })
    assert no_pane.created?
    refute no_pane.complete?
    assert_equal ['no root pane'], no_pane.errors

    nothing = Hiiro::Herdr::TabCreation.new(request: {}, response: nil)
    refute nothing.created?
    assert_equal ['no tab'], nothing.errors
    assert_nil nothing.tab
    assert_nil nothing.location.target
  end

  def test_location_meta_round_trip
    loc = Hiiro::Herdr::Location.new(workspace_id: 'w1', tab_id: 'w1:t2', pane_id: 'w1:p2')
    meta = loc.to_meta
    assert_equal({ 'herdr_workspace' => 'w1', 'herdr_tab' => 'w1:t2', 'herdr_pane' => 'w1:p2' }, meta)
    back = Hiiro::Herdr::Location.from_meta(meta)
    assert back.complete?
    assert_equal 'w1:p2', back.target
  end

  def test_location_target_falls_back
    assert_equal 'w1:t2', Hiiro::Herdr::Location.new(workspace_id: 'w1', tab_id: 'w1:t2').target
    assert_equal 'w1', Hiiro::Herdr::Location.new(workspace_id: 'w1', tab_id: '').target
    assert_nil Hiiro::Herdr::Location.from_meta(nil).target
    assert_equal 'w2', Hiiro::Herdr::Location.new(workspace_id: 'w1').with(workspace_id: 'w2').workspace_id
  end
end
