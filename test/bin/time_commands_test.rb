require 'test_helper'
require 'open3'
require 'rbconfig'

# `h date` and `h time` share one set of registrations (Hiiro::TimeCommands);
# these run the real bins and compare what they print.
class TimeCommandsTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def run_bin(bin, *args, tz: 'America/Chicago')
    Dir.mktmpdir('time-commands-') do |home|
      env = { 'HOME' => home, 'PATH' => "#{File.dirname(RbConfig.ruby)}:/usr/bin:/bin", 'LANG' => 'en_US.UTF-8', 'TZ' => tz,
              'HIIRO_TEST_DB' => 'sqlite::memory:' }
      env['BUNDLE_PATH'] = ENV['BUNDLE_PATH'] if ENV['BUNDLE_PATH']
      out, err, status = Open3.capture3(env, RbConfig.ruby, '-I', File.join(ROOT, 'lib'), File.join(ROOT, 'bin', "h-#{bin}"), *args,
                                        unsetenv_others: true)
      [out, err, status.exitstatus]
    end
  end

  def assert_prints(expected, bin, *args, **kw)
    out, err, code = run_bin(bin, *args, **kw)
    assert_equal [expected, 0], [out, code], err
  end

  def test_points_print_iso8601_for_date_and_clock_for_time
    assert_prints "1970-01-01T00:00:00.000Z\n", 'date', 'from_unix', '0', '--utc'
    assert_prints "00:00:00.000\n", 'time', 'from_unix', '0', '--utc'
    assert_prints "1969-12-31T18:00:00.000-06:00\n", 'date', 'parse', '0'
    assert_prints "18:00:00.000\n", 'time', 'parse', '0'
    assert_prints "2024-09-10T20:26:40.123Z\n", 'date', 'from_unix', '1726000000123', '-u'
    assert_prints "23:26:40.000\n", 'time', 'from_unix', '1726000000', '-m', '-u'
    assert_prints "1970-01-01T00:00:01.500Z\n", 'date', 'from_unix', '1.5', '-u'
    assert_prints "23:59:59.000\n", 'time', 'from_unix', '-1', '-u'
  end

  def test_unix_conversion_and_durations_are_identical_for_both
    %w[date time].each do |bin|
      assert_prints "1\n", bin, 'to_unix', '1970-01-01T00:00:01Z'
      assert_prints "1500\n", bin, 'ts', '1970-01-01T00:00:01.5Z', '--ms'
      assert_prints "1d1h1m1s\n", bin, 'dur', '90061'
      assert_prints "2s\n", bin, 'human', '1500', '--ms'
      assert_prints "-1m1s\n", bin, 'duration', '-61'
      assert_prints "0s\n", bin, 'dur', '1/3'
      assert_prints "2s\n", bin, 'dur', '1.5'
      assert_prints "-2m\n", bin, 'diff', '120', '0'
      assert_prints "2m\n", bin, 'diff', '0', '120'
      assert_prints "1m1s\n", bin, 'diff', '1970-01-01T00:00:00Z', '1970-01-01T00:01:01Z'
      assert_prints "100%\n", bin, 'strftime', '100%'
    end
  end

  def test_fmt_inserts_percent_before_each_letter
    out, = run_bin('date', 'fmt', 'Y-m-d', tz: 'UTC')
    assert_equal "#{Time.now.utc.strftime('%Y-%m-%d')}\n", out
    out, = run_bin('time', 'format', 'H', '-u')
    assert_match(/\A\d\d\n\z/, out)
  end

  def test_now_differs_between_date_and_time
    assert_match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\n\z/, run_bin('date', 'now', '-u').first)
    assert_match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d-0[56]:00\n\z/, run_bin('date', 'now').first)
    assert_match(/\A\d\d:\d\d:\d\d\n\z/, run_bin('time', 'now').first)
    assert_match(/\A\d\d:\d\d:\d\d\.\d{3}\n\z/, run_bin('time', 'now', '-m', '-u').first)
  end

  def test_missing_arguments_print_each_kinds_usage
    {
      %w[date from_unix] => 'usage: h date from_unix <timestamp> [--ms] [--utc]',
      %w[time dur] => 'usage: h time dur <seconds> [--ms]',
      %w[date fmt] => 'usage: h date fmt <strftime-chars-without-percent>',
      %w[time diff 1] => 'usage: h time diff <time-a> <time-b>  (each: time string or unix timestamp)',
      %w[date diff 1] => 'usage: h date diff <date-a> <date-b>  (each: date string or unix timestamp)',
    }.each do |(bin, *args), usage|
      out, err, code = run_bin(bin, *args)
      assert_equal ['', "#{usage}\n", 1], [out, err, code]
    end
  end
end
