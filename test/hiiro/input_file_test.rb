require "test_helper"
require 'rbconfig'

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

  def test_real_editor_exit_status_controls_document_acceptance
    Dir.mktmpdir('hiiro-input-editor-') do |root|
      editor = File.join(root, 'editor')
      [false, true].each do |append|
        [0, 17].each do |status|
          File.write(editor, "#!#{RbConfig.ruby}\nFile.write(ARGV.last, \"a: 2\\n\")\nexit #{status}\n")
          File.chmod(0o700, editor)
          hiiro = Hiiro.allocate
          hiiro.define_singleton_method(:editor) { editor }
          hiiro.define_singleton_method(:vim?) { append }
          input = Hiiro::InputFile.yaml_file(hiiro: hiiro, content: "a: 1\n", append: append)
          begin
            input.parsed_file
            doc = input.edit.document
            assert_equal "a: 1\n", doc.original
            assert_equal "a: 2\n", doc.result
            if status.zero?
              assert doc.editor_succeeded?
              assert doc.valid?
              assert_equal({ 'a' => 2 }, doc.data)
            else
              refute doc.editor_succeeded?
              refute doc.valid?
              assert_nil doc.parsed
              assert_nil doc.data
              assert_nil input.parsed_file
              assert_kind_of RuntimeError, doc.error
            end
          ensure
            path = input.path
            input.cleanup
            refute File.exist?(path)
          end
        end
      end
    end
  end

  def test_unavailable_editor_rejects_existing_valid_yaml
    Dir.mktmpdir('hiiro-input-editor-') do |root|
      hiiro = Hiiro.allocate
      hiiro.define_singleton_method(:editor) { File.join(root, 'missing-editor') }
      input = Hiiro::InputFile.yaml_file(hiiro: hiiro, content: "a: 1\n")
      begin
        doc = input.edit.document
        refute doc.editor_succeeded?
        refute doc.valid?
        assert_equal "a: 1\n", doc.result
        assert_nil doc.data
        assert_nil input.parsed_file
        assert_kind_of RuntimeError, doc.error
      ensure
        input.cleanup
      end
    end
  end

  def test_snapshot_constructor_accepts_parsed_data_without_editor_keyword
    doc = Hiiro::EditedDocument.new(path: 'snapshot.yml', type: :yaml,
                                    original: "a: 1\n", result: "a: 2\n", parsed: { 'a' => 2 })
    assert doc.editor_succeeded?
    assert doc.valid?
    assert_equal({ 'a' => 2 }, doc.data)
  end

  def test_pre_read_caches_follow_successful_editor_document
    input = Hiiro::InputFile.yaml_file(hiiro: @hiiro, content: "a: 1\n")
    assert_equal({ 'a' => 1 }, input.parsed_file)
    assert_equal 'a: 1', input.contents
    @hiiro.next = "a: 2\n"
    doc = input.edit.document
    assert doc.valid?
    assert_equal({ 'a' => 2 }, input.parsed_file)
    assert_equal 'a: 2', input.contents
    input.cleanup
    assert_equal({ 'a' => 2 }, input.parsed_file)
    assert_equal 'a: 2', input.contents
  ensure
    input&.cleanup
  end

  def test_pre_read_caches_do_not_accept_invalid_editor_document
    input = Hiiro::InputFile.yaml_file(hiiro: @hiiro, content: "a: 1\n")
    assert_equal({ 'a' => 1 }, input.parsed_file)
    assert_equal 'a: 1', input.contents
    @hiiro.next = "[broken\n"
    doc = input.edit.document
    assert doc.editor_succeeded?
    refute doc.valid?
    assert_kind_of Psych::SyntaxError, doc.error
    assert_nil doc.data
    assert_nil input.parsed_file
    assert_equal '[broken', input.contents
    input.cleanup
    assert_nil input.parsed_file
    assert_equal '[broken', input.contents
  ensure
    input&.cleanup
  end

  def test_text_document_parses_lines_and_keep_survives_cleanup
    @hiiro.next = "/a b\n\n/c\n"
    input = Hiiro::InputFile.new(hiiro: @hiiro, type: :text, content: "/a b\n", prefix: 'bundle-')
    doc = input.edit.document
    assert_equal ['/a b', '', '/c'], doc.data
    assert doc.valid?
    assert input.path.end_with?('.txt')

    Dir.mktmpdir do |dir|
      kept = input.keep(dir: dir)
      input.cleanup
      assert_match(%r{\A#{Regexp.escape(dir)}/bundle-\d{14}-\h{6}\.txt\z}, kept)
      assert_equal "/a b\n\n/c\n", File.read(kept)
    end
  ensure
    input&.cleanup
  end
end
