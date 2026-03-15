require 'tempfile'
require 'yaml'

class Hiiro
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

    def edit
      if append && hiiro.vim?
        system(hiiro.editor, '+$', tmpfile.path)
      else
        hiiro.edit_files(tmpfile.path)
      end
      self
    end

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
    def parsed_file
      @parsed_file ||= case type
      when :yaml
        YAML.safe_load_file(tmpfile.path) rescue nil
      when :md
        require 'front_matter_parser'
        FrontMatterParser::Parser.parse_file(tmpfile.path)
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
  end
end
