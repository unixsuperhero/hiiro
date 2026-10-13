require_relative "../test_helper"

class RequirePathsTest < Minitest::Test
  def test_hiiro_require_relative_targets_exist
    root = File.expand_path("../../lib", __dir__)
    hiiro_rb = File.join(root, "hiiro.rb")

    missing = File.readlines(hiiro_rb).filter_map do |line|
      target = line[/\Arequire_relative\s+["']([^"']+)["']/, 1]
      next unless target

      path = File.join(root, "#{target}.rb")
      path unless File.file?(path)
    end

    assert_empty missing
  end

  def test_every_lazily_loaded_constant_is_defined_by_its_file
    undefined = Hiiro::DOMAIN.values.flatten.reject { |name| Hiiro.const_get(name).is_a?(Module) }

    assert_empty undefined
  end
end
