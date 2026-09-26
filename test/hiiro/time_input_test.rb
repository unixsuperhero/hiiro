require "test_helper"

class TimeInputTest < Minitest::Test
  def test_digits_parse_as_unix_seconds
    t = Hiiro::TimeInput.parse('1726000000')
    assert_equal :seconds, t.unit
    assert_equal Time.at(1_726_000_000), t.time
    assert_equal 1_726_000_000, t.unix_seconds
  end

  def test_long_digits_auto_detect_milliseconds
    t = Hiiro::TimeInput.parse('1726000000123')
    assert_equal :milliseconds, t.unit
    assert_equal Time.at(Rational(1_726_000_000_123, 1000)), t.time
    assert_equal 1_726_000_000_123, t.unix_milliseconds
  end

  def test_explicit_ms_flag
    t = Hiiro::TimeInput.parse('1726000000', ms: true)
    assert_equal Time.at(Rational(1_726_000_000, 1000)), t.time
  end

  def test_now_and_blank
    now = Time.at(100)
    assert_equal now, Hiiro::TimeInput.parse('now', now: now).time
    assert_equal now, Hiiro::TimeInput.parse(nil, now: now).time
    assert_equal :now, Hiiro::TimeInput.parse('', now: now).unit
  end

  def test_text_uses_time_parse
    t = Hiiro::TimeInput.parse('2026-09-22T10:00:00Z')
    assert_equal :text, t.unit
    assert_equal Time.parse('2026-09-22T10:00:00Z'), t.time
  end

  def test_difference_is_a_duration
    a = Hiiro::TimeInput.parse('100')
    b = Hiiro::TimeInput.parse('190')
    assert_equal '1m30s', a.difference(b).compact
    assert_equal '-1m30s', b.difference(a).compact
  end

  def test_utc_keeps_raw_and_unit
    t = Hiiro::TimeInput.parse('1726000000').utc
    assert_equal '1726000000', t.raw
    assert t.time.utc?
  end
end
