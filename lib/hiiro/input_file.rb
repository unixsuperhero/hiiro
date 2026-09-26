require 'tempfile'
require 'yaml'

class Hiiro
  # Snapshot of an InputFile after the editor closed: what was there before,
  # what the user left, and how it parsed.
  class EditedDocument
    attr_reader :path, :type, :original, :result, :parsed, :error

    def initialize(path:, type:, original:, result:, parsed: nil, error: nil)
      @path = path
      @type = type
      @original = original
      @result = result
      @parsed = parsed
      @error = error
    end

    alias contents result
    alias data parsed

    def changed? = original.to_s != result
    def empty?   = result.to_s.strip.empty?
    def valid?   = error.nil?
  end

  class InputFile
    EXTENSIONS = { yaml: '.yml', md: '.md' }.freeze

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
      if append && hiiro.vim?
        system(hiiro.editor, '+$', tmpfile.path)
      else
        hiiro.edit_files(tmpfile.path)
      end
      @document = snapshot(permitted_classes: permitted_classes)
      self
    end

    # The EditedDocument from the last #edit; nil before editing.
    attr_reader :document

    def path
      tmpfile.path
    end

    # The raw text the user wrote, stripped of leading/trailing whitespace.
    def contents
      @contents ||= File.read(tmpfile.path).strip
    end

    # Parses the file contents according to type:
    #   :yaml → Hash or Array (via YAML.safe_load)
    #   :md   → FrontMatterParser::Document (call .front_matter, .content)
    def parsed_file(permitted_classes: [])
      @parsed_file ||= begin
        parse(permitted_classes: permitted_classes)
      rescue Psych::Exception
        nil
      end
    end

    def empty?
      contents.empty?
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
      end
    end

    def snapshot(permitted_classes:)
      result = File.read(tmpfile.path)
      EditedDocument.new(path: path, type: type, original: content, result: result,
                         parsed: parse(permitted_classes: permitted_classes))
    rescue Psych::Exception => e
      EditedDocument.new(path: path, type: type, original: content, result: result, error: e)
    end
  end
end
