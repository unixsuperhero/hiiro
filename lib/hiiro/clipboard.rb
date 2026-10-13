require 'open3'
require 'tmpdir'

class Hiiro
  # The macOS clipboard adapters (pbpaste, pngpaste, pbcopy, osascript).
  # Reads return a Payload with the exact bytes, or a Failure naming why.
  #
  #   Clipboard.text   # => Payload{ source: :clipboard_text, content_type: 'text/plain', bytes: "..." }
  #   Clipboard.image  # => Failure{ status: :empty_clipboard | :missing_image_tool | :adapter_failed, detail: '...' }
  module Clipboard
    Payload = Struct.new(:source, :content_type, :bytes, keyword_init: true) do
      def ok? = true
      def extension = content_type == 'image/png' ? 'png' : 'txt'
    end

    Failure = Struct.new(:status, :detail, keyword_init: true) do
      def ok? = false
    end

    # pngpaste's message when the clipboard holds no image.
    NO_IMAGE = /no (png|image) data/i

    module_function

    def text
      out, err, status = Open3.capture3('pbpaste', binmode: true)
      return Failure.new(status: :adapter_failed, detail: "pbpaste failed: #{err.strip}") unless status.success?
      return Failure.new(status: :empty_clipboard, detail: 'Clipboard is empty') if out.empty?

      Payload.new(source: :clipboard_text, content_type: 'text/plain', bytes: out)
    rescue Errno::ENOENT
      Failure.new(status: :adapter_failed, detail: 'pbpaste not found')
    end

    # pngpaste writes to a file in a directory this method owns and removes.
    def image
      return Failure.new(status: :missing_image_tool, detail: 'pngpaste not found') unless Bins.which('pngpaste')

      Dir.mktmpdir('hiiro-clipboard-') do |dir|
        path = File.join(dir, 'clipboard.png')
        _, err, status = Open3.capture3('pngpaste', path)
        unless status.success? && File.file?(path) && File.size(path).positive?
          return Failure.new(status: :empty_clipboard, detail: 'No image in clipboard') if err.match?(NO_IMAGE)

          return Failure.new(status: :adapter_failed, detail: "pngpaste failed: #{err.strip.empty? ? "exit #{status.exitstatus}" : err.strip}")
        end
        Payload.new(source: :clipboard_image, content_type: 'image/png', bytes: File.binread(path))
      end
    end

    def copy_text(text)
      _, status = Open3.capture2('pbcopy', stdin_data: text, binmode: true)
      status.success?
    rescue Errno::ENOENT
      false
    end

    def copy_image(path)
      system('osascript', '-e', "set the clipboard to (read (POSIX file #{path.inspect}) as «class PNGf»)",
             out: File::NULL, err: File::NULL) == true
    end
  end
end
