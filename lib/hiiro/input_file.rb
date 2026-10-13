require 'tempfile'
require 'fileutils'
require 'securerandom'
require 'yaml'

class Hiiro
  # Snapshot of an InputFile after the editor closed: what was there before,
  # what the user left, and how it parsed.
  class EditedDocument
    attr_reader :path, :type, :original, :result, :parsed, :error

    def initialize(path:, type:, original:, result:, parsed: nil, error: nil, editor_succeeded: true)
      @path = path
      @type = type
      @original = original
      @result = result
      @editor_succeeded = editor_succeeded == true
      @parsed = parsed if editor_succeeded?
      @error = error || (RuntimeError.new('Editor did not exit successfully') unless editor_succeeded?)
    end

    alias contents result
    alias data parsed

    def changed? = original.to_s != result
    def empty?   = result.to_s.strip.empty?
    def editor_succeeded? = @editor_succeeded
    def valid?   = editor_succeeded? && error.nil?
  end

  class InputFile
    EXTENSIONS = { yaml: '.yml', md: '.md', text: '.txt' }.freeze

    def self.yaml_file(hiiro:, content: nil, append: false, prefix: 'edit-')
      new(hiiro: hiiro, type: :yaml, content: content, append: append, prefix: prefix)
    end

    def self.md_file(hiiro:, content: nil, append: false, prefix: 'edit-')
      new(hiiro: hiiro, type: :md, content: content, append: append, prefix: prefix)
    end

    attr_reader :hiiro, :type, :content, :append, :prefix

    def initialize(hiiro:, type: :md, content: nil, append: false, prefix: 'edit-')
      @hiiro   = hiiro
      @type    = type
      @content = content
      @append  = append
      @prefix  = prefix
    end

    # Lazily creates, pre-fills, and closes the tempfile.
    # The file is not created until it's first needed.
    def tmpfile
      @tmpfile ||= begin
        tf = Tempfile.new([prefix, EXTENSIONS.fetch(type)])
        tf.write(content) if content
        tf.close
        tf
      end
    end

    # Runs the editor, then captures the result as #document. Returns self.
    def edit(permitted_classes: [])
      @parsed_file = @contents = nil
      editor_succeeded = if append && hiiro.vim?
        system(hiiro.editor, '+$', tmpfile.path)
      else
        hiiro.edit_files(tmpfile.path)
      end
      @document = snapshot(permitted_classes: permitted_classes, editor_succeeded: editor_succeeded)
      self
    end

    # The EditedDocument from the last #edit; nil before editing.
    attr_reader :document

    def path
      tmpfile.path
    end

    # The raw text the user wrote, stripped of leading/trailing whitespace.
    def contents
      @contents ||= (document ? document.result : File.read(tmpfile.path)).strip
    end

    # Parses the file contents according to type:
    #   :yaml → Hash or Array (via YAML.safe_load)
    #   :md   → FrontMatterParser::Document (call .front_matter, .content)
    #   :text → Array of lines without newlines
    def parsed_file(permitted_classes: [])
      return document.data if document

      @parsed_file ||= begin
        parse(permitted_classes: permitted_classes)
      rescue Psych::Exception
        nil
      end
    end

    def empty?
      contents.empty?
    end

    # Copies the edited text to a durable file and returns its path, so a
    # rejected edit survives the tempfile (which Ruby deletes at exit).
    def keep(dir: File.join(Config::DATA_DIR, 'edits'))
      FileUtils.mkdir_p(dir)
      kept = File.join(dir, "#{prefix}#{Time.now.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(3)}#{EXTENSIONS.fetch(type)}")
      File.write(kept, document ? document.result : File.read(tmpfile.path))
      kept
    end

    # Deletes the tempfile. Call when done with the input.
    # Safe to call even if the file was never materialized.
    def cleanup
      @tmpfile&.unlink
    end

    private

    def parse(permitted_classes:)
      case type
      when :yaml
        YAML.safe_load_file(tmpfile.path, permitted_classes:)
      when :md
        require 'front_matter_parser'
        FrontMatterParser::Parser.parse_file(tmpfile.path)
      when :text
        File.readlines(tmpfile.path, chomp: true)
      end
    end

    def snapshot(permitted_classes:, editor_succeeded:)
      result = File.read(tmpfile.path)
      unless editor_succeeded == true
        return EditedDocument.new(path: path, type: type, original: content, result: result,
                                  editor_succeeded: editor_succeeded)
      end
      EditedDocument.new(path: path, type: type, original: content, result: result,
                         parsed: parse(permitted_classes: permitted_classes))
    rescue Psych::Exception => e
      EditedDocument.new(path: path, type: type, original: content, result: result, error: e)
    end
  end
end
