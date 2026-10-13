require 'test_helper'
require_relative '../support/cli_sandbox'

# `h encode` and `h decode` share Hiiro::Codec: one format table, one input
# reader. These run the real bins and compare bytes.
class CodecTest < Minitest::Test
  include CliSandbox

  BYTES = "a\0b\xff\n+ /%".b

  def setup = setup_sandbox
  def teardown = teardown_sandbox

  def test_byte_safe_formats_round_trip_nul_and_high_bytes
    { 'base64' => 'YQBi/worIC8l', 'b64url' => 'YQBi_worIC8l', 'hex' => '610062ff0a2b202f25', 'percent' => 'a%00b%FF%0A%2B%20%2F%25',
      'rot13' => "n\0o\xff\n+ /%".b }.each do |format, encoded|
      out, err, code = run_bin('h-encode', format, stdin: BYTES)
      assert_equal [encoded.b, '', 0], [out.b, err, code], format
      back, = run_bin('h-decode', format, stdin: out)
      assert_equal BYTES, back.b, format
    end
  end

  def test_file_and_explicit_dash_inputs_and_unpadded_base64url
    File.binwrite(File.join(@home, 'in.bin'), "\xfb\xff")
    assert_equal ['-_8', 0], run_bin('h-encode', 'base64url', 'in.bin').values_at(0, 2)
    assert_equal ['+/8=', 0], run_bin('h-encode', 'b64', 'in.bin').values_at(0, 2)
    assert_equal ['6869', 0], run_bin('h-encode', 'hex', '-', stdin: 'hi').values_at(0, 2)
    assert_equal ['', "File not found: #{@home}/missing\n", 1], run_bin('h-encode', 'hex', 'missing')
    assert_equal ['', "Expected at most one input file.\n", 1], run_bin('h-decode', 'hex', 'a', 'b')
  end

  def test_percent_keeps_plus_and_form_decodes_it_as_space
    assert_equal ['a+b', '', 0], run_bin('h-decode', 'uri', stdin: 'a+b')
    assert_equal ['a b', '', 0], run_bin('h-decode', 'form', stdin: 'a+b')
    assert_equal ['a+b%2F', 0], run_bin('h-encode', 'form', stdin: 'a b/').values_at(0, 2)
    assert_equal ['a%20b%2F', 0], run_bin('h-encode', 'url', stdin: 'a b/').values_at(0, 2)
  end

  def test_malformed_input_fails_without_output
    [['uri', '%zz'], ['percent', '%4'], ['form', '%zz'], ['hex', 'abc'], ['hex', 'zz'], ['base64', 'a'], ['b64url', 'a+'],
     ['json', '[1]'], ['json', '"unterminated']].each do |format, input|
      out, err, code = run_bin('h-decode', format, stdin: input)
      assert_equal ['', 1], [out, code], "#{format} #{input}"
      assert_match(/\ADecode failed: /, err, "#{format} #{input}")
    end
    assert_equal ['', "Decode failed: input is valid JSON, but is not a JSON string\n", 1], run_bin('h-decode', 'json', stdin: '[1]')
  end

  def test_text_formats_require_utf8_and_json_decodes_strings_only
    assert_equal ['', "JSON encoding requires valid UTF-8 input.\n", 1], run_bin('h-encode', 'json', stdin: "\xff".b)
    assert_equal ['', "HTML encoding requires valid UTF-8 input.\n", 1], run_bin('h-encode', 'html', stdin: "\xff".b)
    assert_equal ['"a\\"b\\n"', 0], run_bin('h-encode', 'json-string', stdin: "a\"b\n").values_at(0, 2)
    assert_equal ["a\"b\n", 0], run_bin('h-decode', 'json', stdin: '"a\"b\n"').values_at(0, 2)
    assert_equal ['&lt;a&amp;b&gt;', 0], run_bin('h-encode', 'html', stdin: '<a&b>').values_at(0, 2)
    assert_equal ['<a&b>', 0], run_bin('h-decode', 'html-entities', stdin: '&lt;a&amp;b&gt;').values_at(0, 2)
  end

  def test_help_is_the_default
    out, _, code = run_bin('h-decode')
    assert_equal 0, code
    assert_includes out, "Usage: h decode <format> [file]\n"
    assert_includes out, "  base64url, b64url        URL-safe Base64 (whitespace/padding optional)\n"
    assert_equal out.sub('decode', 'encode').sub('decoded', 'encoded').lines.first, run_bin('h-encode', 'help').first.lines.first
  end

  # With a terminal and no file, the clipboard is read (fixture pbpaste).
  def test_terminal_input_reads_the_clipboard
    File.write(File.join(@bin, 'pbpaste'), "#!/bin/sh\nprintf 'hi there'\n")
    File.chmod(0o755, File.join(@bin, 'pbpaste'))
    output = +''
    PTY.spawn(sandbox_env, *bin_argv('h-encode', 'b64'), chdir: @home, unsetenv_others: true) do |reader, _writer, pid|
      begin
        loop { output << reader.readpartial(4096) }
      rescue EOFError, Errno::EIO
      end
      assert_equal 0, Process.wait2(pid).last.exitstatus
    end
    assert_equal 'aGkgdGhlcmU=', output
  end
end
