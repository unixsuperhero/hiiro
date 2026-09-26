require "test_helper"

class DurationTest < Minitest::Test
  def test_parse_unit_table
    assert_equal 30,      Hiiro::Duration.parse('30s').seconds
    assert_equal 900,     Hiiro::Duration.parse('15m').seconds
    assert_equal 7200,    Hiiro::Duration.parse('2h').seconds
    assert_equal 86_400,  Hiiro::Duration.parse('1d').seconds
    assert_equal 604_800, Hiiro::Duration.parse('1w').seconds
    assert_equal 300,     Hiiro::Duration.parse('5M').seconds
  end

  def test_parse_returns_nil_for_bad_input
    assert_nil Hiiro::Duration.parse('x')
    assert_nil Hiiro::Duration.parse(nil)
    assert_nil Hiiro::Duration.parse('15 m')
  end

  def test_compact_matches_legacy_human_duration
    assert_equal '0s',         Hiiro::Duration.seconds(0).compact
    assert_equal '1m1s',       Hiiro::Duration.seconds(61).compact
    assert_equal '1d1h1m1s',   Hiiro::Duration.seconds(90_061).compact
    assert_equal '-1h1m1s',    Hiiro::Duration.seconds(-3661).compact
    assert_equal '2s',         Hiiro::Duration.seconds(Rational(1500, 1000)).compact
    assert_equal '1m30s',      Hiiro::Duration.milliseconds(90_000).compact
  end

  def test_components_and_clock
    d = Hiiro::Duration.seconds(90_061)
    assert_equal({ days: 1, hours: 1, minutes: 1, seconds: 1 }, d.components)
    assert_equal '25:01:01', d.clock
  end
end
