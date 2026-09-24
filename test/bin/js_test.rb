require "test_helper"
require "json"
require "open3"
require "rbconfig"

class JsTest < Minitest::Test
  def test_add_preserves_shell_commands_and_argument_boundaries
    Dir.mktmpdir("h-js") do |dir|
      path = File.join(dir, "package.json")
      File.write(path, JSON.generate({ "name" => "example", "scripts" => { "existing" => "echo keep" } }))
      bin = File.expand_path("../../bin/h-js", __dir__)
      lib = File.expand_path("../../lib", __dir__)
      command = <<~'SH'.strip
        printf '%s\n' 'double"quote' 'C:\tmp\file' '$HOME' 'line
        break' '雪' && printf 'done\n'
      SH
      stdout, stderr, status = Open3.capture3({ "RUBYLIB" => lib }, RbConfig.ruby, bin, "add", "check", command, chdir: dir)
      assert status.success?, stdout + stderr
      package = JSON.parse(File.read(path))
      assert_equal command, package.fetch("scripts").fetch("check")
      assert_equal "echo keep", package.fetch("scripts").fetch("existing")
      assert_equal "example", package.fetch("name")
      stdout, stderr, status = Open3.capture3("/bin/sh", "-c", package.fetch("scripts").fetch("check"), chdir: dir)
      assert status.success?, stderr
      assert_equal "double\"quote\nC:\\tmp\\file\n$HOME\nline\nbreak\n雪\ndone\n", stdout

      stdout, stderr, status = Open3.capture3({ "RUBYLIB" => lib }, RbConfig.ruby, bin, "add", "args", "--", "printf", "%s\\n", "two words", "a'b", "$HOME", "&&", chdir: dir)
      assert status.success?, stdout + stderr
      script = JSON.parse(File.read(path)).fetch("scripts").fetch("args")
      stdout, stderr, status = Open3.capture3("/bin/sh", "-c", script, chdir: dir)
      assert status.success?, stderr
      assert_equal "two words\na'b\n$HOME\n&&\n", stdout

      original = File.read(path)
      _, _, status = Open3.capture3({ "RUBYLIB" => lib }, RbConfig.ruby, bin, "add", "check", "echo replaced", chdir: dir)
      refute status.success?
      assert_equal original, File.read(path)
    end
  end
end
