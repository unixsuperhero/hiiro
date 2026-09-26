require "test_helper"

class InputFileTest < Minitest::Test
  # Minimal editor context: "editing" overwrites the file with @next.
  class FakeHiiro
    attr_accessor :next
    def editor = 'fake-editor'
    def vim? = false
    def edit_files(*files)
      File.write(files.first, @next) if @next
      true
    end
  end

  def setup
    @hiiro = FakeHiiro.new
  end

  def test_document_captures_original_result_and_parsed_yaml
    @hiiro.next = "- text: hello\n  status: done\n"
    input = Hiiro::InputFile.yaml_file(hiiro: @hiiro, content: "- text: ''\n")
    doc = input.edit.document

    assert_equal "- text: ''\n", doc.original
    assert_equal "- text: hello\n  status: done\n", doc.result
    assert_equal [{ 'text' => 'hello', 'status' => 'done' }], doc.data
    assert doc.changed?
    assert doc.valid?
    refute doc.empty?
    assert_equal input.path, doc.path
  ensure
    input&.cleanup
  end

  def test_document_unchanged_and_empty
    input = Hiiro::InputFile.yaml_file(hiiro: @hiiro, content: "")
    doc = input.edit.document

    refute doc.changed?
    assert doc.empty?
    assert_nil doc.data
  ensure
    input&.cleanup
  end

  def test_document_retains_parse_error
    @hiiro.next = "key: [unclosed\n"
    input = Hiiro::InputFile.yaml_file(hiiro: @hiiro, content: "")
    doc = input.edit.document

    refute doc.valid?
    assert_kind_of Psych::Exception, doc.error
    assert_equal "key: [unclosed\n", doc.contents
    assert_nil input.parsed_file
  ensure
    input&.cleanup
  end

  def test_document_is_nil_before_edit
    input = Hiiro::InputFile.yaml_file(hiiro: @hiiro, content: "a: 1\n")
    assert_nil input.document
    assert_equal({ 'a' => 1 }, input.parsed_file)
  ensure
    input&.cleanup
  end
end
