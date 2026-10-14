require "test_helper"
require_relative "tuios_fake_runner"

class TuiosListingTest < Minitest::Test
  include TuiosFixtures

  def load(runner, hosts: false) = Hiiro::TuiosListing.load(runner:, hosts:)

  def shape(listing) = listing.windows.map { |w| [w.host, w.session, w.workspace, w.index, w.id, w.cwd, w.minimized] }

  def test_windows_merge_list_windows_by_id_and_sort_by_host_session_workspace_index
    runner = TuiosFakeRunner.new(answers)
    listing = load(runner)

    assert_equal [
      ["local", "alpha", 1, 0, "id-a2", HIIRO, true],
      ["local", "alpha", 2, 0, "id-a3", nil, false],
      ["local", "alpha", 2, 1, "id-a1", HIIRO, false],
      ["local", "zeta", 1, 0, "id-z1", FLEET, false],
    ], shape(listing)
    assert_equal [
      %w[ls --json],
      %w[list-windows -s zeta --json],
      %w[list-windows -s alpha --json],
      %w[list-attention --json],
    ], runner.calls
  end

  def test_window_fields_come_from_ls_with_list_windows_details
    listing = load(TuiosFakeRunner.new(answers))
    a1, a2, a3, z1 = listing.windows.sort_by(&:id)

    assert_equal "π > Implement JSON Task Status Management", a1.title
    assert_equal %w[done omp bun], [a1.state, a1.harness, a1.cmd]
    assert_equal [false, false, nil], [a1.focused, a1.minimized, a1.message]
    assert_equal [true, true, nil, "working"], [a2.focused, a2.minimized, a2.cmd, a2.state]
    assert_equal ["needs_input", "claude-code", "Open the file?", "claude"], [a3.state, a3.harness, a3.message, a3.cmd]
    assert_equal ["cld", "Configuring distinct Starship prompts"], [z1.cmd, z1.message]
    assert_equal %i[window window], [a1.kind, z1.kind]
    assert_equal %w[id-a1 alpha], [a1.key, a1.label]
  end

  def test_a_session_without_windows_lists_no_windows_and_asks_nothing_more
    runner = TuiosFakeRunner.new(answers)
    listing = load(runner)

    assert_equal %w[zeta alpha beta], listing.sessions.map(&:name)
    assert_equal [true, false, false], listing.sessions.map(&:attached)
    assert_equal ["/", "fleet", nil], listing.sessions.map(&:dir)
    refute_includes runner.calls, %w[list-windows -s beta --json]
  end

  def test_state_defaults_to_none_when_ls_omits_it
    sessions = ls_sessions
    sessions[0]["windows"][0].delete("agent_state")
    listing = load(TuiosFakeRunner.new(answers.merge(%w[ls --json] => JSON.generate(sessions))))

    assert_equal "none", listing.windows.find { |w| w.id == "id-z1" }.state
  end

  def test_a_failing_list_windows_keeps_the_ls_windows_with_index_zero
    failing = answers.merge(%w[list-windows -s alpha --json] => Hiiro::Error.new("tuios list-windows failed"))
    listing = load(TuiosFakeRunner.new(failing))

    assert_equal [
      ["local", "alpha", 1, 0, "id-a2", nil, false],
      ["local", "alpha", 2, 0, "id-a1", nil, false],
      ["local", "alpha", 2, 0, "id-a3", nil, false],
      ["local", "zeta", 1, 0, "id-z1", FLEET, false],
    ], shape(listing)
  end

  def test_a_failing_ls_propagates
    assert_raises(Hiiro::Error) { load(TuiosFakeRunner.new({})) }
  end

  def test_attention_keeps_only_nonzero_counts
    assert_equal({ "ask" => 1, "finished" => 2 }, load(TuiosFakeRunner.new(answers)).attention)
  end

  def test_attention_is_empty_when_list_attention_fails
    failing = answers.merge(%w[list-attention --json] => Hiiro::Error.new("no daemon"))

    assert_equal({}, load(TuiosFakeRunner.new(failing)).attention)
    assert_equal({}, load(TuiosFakeRunner.new(answers.merge(%w[list-attention --json] => "not json"))).attention)
  end

  def test_hosts_adds_one_remote_row_per_session_after_the_local_windows
    runner = TuiosFakeRunner.new(answers)
    listing = load(runner, hosts: true)
    remote = listing.windows.select { |row| row.kind == :session }

    assert_equal 4, listing.windows.count { |row| row.kind == :window }
    assert_equal remote, listing.windows.last(2)
    assert_equal [["m3pro", "fleet", 1, nil], ["m3pro", "m3pro", 3, "done"]], remote.map { |r| [r.host, r.session, r.windows, r.state] }
    assert_equal ["m3pro:fleet", "m3pro:m3pro"], remote.map(&:key)
    assert_equal %w[zeta alpha beta m3pro fleet], listing.sessions.map(&:name)
    assert_equal %w[local local local m3pro m3pro], listing.sessions.map(&:host)
    assert_includes runner.calls, %w[ls --all-hosts --json]
  end

  def test_hosts_false_never_asks_for_all_hosts
    runner = TuiosFakeRunner.new(answers)
    load(runner)

    refute_includes runner.calls, %w[ls --all-hosts --json]
  end

  def test_setting_hosts_then_reload_switches_the_remote_rows
    listing = load(TuiosFakeRunner.new(answers))

    assert_equal 4, listing.windows.length

    listing.hosts = true
    listing.reload

    assert_equal 6, listing.windows.length

    listing.hosts = false
    listing.reload

    assert_equal 4, listing.windows.length
  end
end
