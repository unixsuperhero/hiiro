require 'tempfile'
require 'yaml'

class Hiiro
  # Represents text the user typed into a temporary file via their editor.
  #
  # Handles the full lifecycle: create tempfile → optionally pre-fill →
  # open in editor → read content back → cleanup.
  #
  # Usage (via the hiiro convenience method):
  #
  #   # Empty tempfile, read text back
  #   input = edit_tempfile(prefix: 'claude-', ext: '.md')
  #   next if input.empty?
  #   use(input.text)
  #   input.cleanup
  #
  #   # Pre-fill with content, read YAML back
  #   input = edit_tempfile(prefix: 'tag-', ext: '.yml', content: data.to_yaml)
  #   result = input.yaml
  #   input.cleanup
  #
  #   # Pre-fill with frontmatter, position cursor at end for appending
  #   input = edit_tempfile(prefix: 'hq-', ext: '.md', content: fm, append: true)
  #   content = input.text
  #   input.cleanup
  #
  class EditorInput
    def self.open(hiiro, prefix: 'edit-', ext: '.md', content: nil, append: false)
      new(hiiro, prefix:, ext:, content:, append:).tap(&:edit)
    end

    def initialize(hiiro, prefix: 'edit-', ext: '.md', content: nil, append: false)
      @hiiro   = hiiro
      @append  = append
      @tmpfile = Tempfile.new([prefix, ext])
      @tmpfile.write(content) if content
      @tmpfile.close
    end

    # Opens the tempfile in the editor. Called automatically by .open.
    def edit
      if @append && @hiiro.vim?
        system(@hiiro.editor, '+$', @tmpfile.path)
      else
        @hiiro.edit_files(@tmpfile.path)
      end
      self
    end

    # The text the user wrote, stripped of leading/trailing whitespace.
    def text
      @text ||= File.read(@tmpfile.path).strip
    end

    # The text parsed as YAML. Returns nil if empty or unparseable.
    def yaml(permitted_classes: [])
      @yaml ||= YAML.safe_load_file(@tmpfile.path, permitted_classes:) rescue nil
    end

    def empty?
      text.empty?
    end

    def path
      @tmpfile.path
    end

    # Deletes the tempfile. Call when you're done with the input.
    def cleanup
      @tmpfile.unlink
    end
  end
end
