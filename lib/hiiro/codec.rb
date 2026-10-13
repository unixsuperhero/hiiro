require 'base64'
require 'cgi'
require 'json'
require 'uri'

class Hiiro
  # One codec table shared by `h encode` and `h decode`, one input reader, and
  # one arity check. Values are bytes in and bytes out; nothing adds a newline.
  #
  #   Codec.find('b64url')                # => Format{ name: 'base64url', aliases: ['b64url'], ... }
  #   Codec.encode(Codec.find('hex'), "a\0")   # => "6100"
  #   Codec.decode(Codec.find('form'), 'a+b')  # => "a b"
  #   Codec.register(hiiro, :decode)      # one subcommand per format, plus help and the default
  module Codec
    class Error < StandardError; end

    # utf8: the label for "<label> encoding requires valid UTF-8 input." when
    # encoding needs text; nil when any bytes encode.
    Format = Struct.new(:name, :aliases, :utf8, :encode_help, :decode_help, :encoder, :decoder, keyword_init: true) do
      def tokens = [name, *aliases]
      def label = tokens.join(', ')
    end

    ROT13 = ->(bytes) { bytes.tr('A-Za-z', 'N-ZA-Mn-za-m') }

    FORMATS = [
      Format.new(name: 'base64', aliases: %w[b64], encode_help: 'Standard Base64',
                 decode_help: 'Standard Base64 (whitespace/padding optional)',
                 encoder: ->(bytes) { Base64.strict_encode64(bytes) },
                 decoder: ->(bytes) { Codec.decode_base64(bytes, urlsafe: false) }),
      Format.new(name: 'base64url', aliases: %w[b64url], encode_help: 'URL-safe Base64 without padding',
                 decode_help: 'URL-safe Base64 (whitespace/padding optional)',
                 encoder: ->(bytes) { Base64.urlsafe_encode64(bytes, padding: false) },
                 decoder: ->(bytes) { Codec.decode_base64(bytes, urlsafe: true) }),
      Format.new(name: 'hex', aliases: %w[base16 b16], encode_help: 'Lowercase hexadecimal', decode_help: 'Hexadecimal',
                 encoder: ->(bytes) { bytes.unpack1('H*') },
                 decoder: ->(bytes) { Codec.decode_hex(bytes) }),
      Format.new(name: 'uri', aliases: %w[url percent], encode_help: 'RFC 3986 URI-component percent encoding',
                 decode_help: 'RFC 3986 URI-component percent encoding',
                 encoder: ->(bytes) { Codec.percent_encode(bytes) },
                 decoder: ->(bytes) { Codec.percent_decode(bytes) }),
      Format.new(name: 'form', aliases: %w[query], utf8: 'Form', encode_help: 'application/x-www-form-urlencoded text',
                 decode_help: 'application/x-www-form-urlencoded text',
                 encoder: ->(text) { URI.encode_www_form_component(text) },
                 decoder: ->(bytes) { URI.decode_www_form_component(bytes) }),
      Format.new(name: 'html', aliases: %w[html-entities], utf8: 'HTML', encode_help: 'HTML entities', decode_help: 'HTML entities',
                 encoder: ->(text) { CGI.escapeHTML(text) },
                 decoder: ->(bytes) { CGI.unescapeHTML(bytes) }),
      Format.new(name: 'json', aliases: %w[json-string], utf8: 'JSON', encode_help: 'JSON string literal',
                 decode_help: 'JSON string literal',
                 encoder: ->(text) { JSON.generate(text) },
                 decoder: ->(bytes) { Codec.decode_json(bytes) }),
      Format.new(name: 'rot13', aliases: [], encode_help: 'ROT13 (self-inverse)', decode_help: 'ROT13 (self-inverse)',
                 encoder: ROT13, decoder: ROT13)
    ].freeze

    module_function

    def find(token) = FORMATS.find { |format| format.tokens.include?(token.to_s) }

    def encode(format, bytes)
      input = bytes.b
      if format.utf8
        input = input.force_encoding(Encoding::UTF_8)
        raise Error, "#{format.utf8} encoding requires valid UTF-8 input." unless input.valid_encoding?
      end
      format.encoder.call(input).b
    end

    def decode(format, bytes)
      format.decoder.call(bytes.b).b
    rescue ArgumentError, JSON::ParserError, URI::InvalidURIError => e
      raise Error, "Decode failed: #{e.message}"
    end

    # File, then explicit '-' (stdin), then piped stdin, then the clipboard.
    def input_bytes(args, stdin: $stdin, clipboard: -> { Clipboard.text })
      raise Error, 'Expected at most one input file.' if args.length > 1

      path = args.first
      if path && path != '-'
        expanded = File.expand_path(path)
        raise Error, "File not found: #{expanded}" unless File.file?(expanded)

        return File.binread(expanded)
      end
      return stdin.binmode.read if path == '-' || !stdin.tty?

      clipboard_bytes(clipboard.call)
    end

    # An empty clipboard is empty input, as `pbpaste` printing nothing was.
    def clipboard_bytes(read)
      return read.bytes if read.ok?
      return ''.b if read.status == :empty_clipboard
      raise Error, 'No piped input or file, and pbpaste is unavailable.' if read.detail == 'pbpaste not found'

      raise Error, read.detail
    end

    def help(direction)
      verb = direction == :encode ? 'encoded' : 'decoded'
      rows = FORMATS.map do |fmt|
        format('  %-25s%s', fmt.label, direction == :encode ? fmt.encode_help : fmt.decode_help)
      end
      <<~HELP
        Usage: h #{direction} <format> [file]

        Reads a file, piped stdin, or the macOS clipboard (when neither is given).
        Writes the #{verb} value to stdout without adding a newline.

        Formats:
        #{rows.join("\n")}

        Use - as the file to explicitly read stdin.
      HELP
    end

    def run(direction, format, args, out: $stdout)
      bytes = input_bytes(args)
      result = direction == :encode ? encode(format, bytes) : decode(format, bytes)
      out.binmode.write(result)
      true
    rescue Error => e
      warn e.message
      exit 1
    end

    def register(hiiro, direction)
      FORMATS.each do |format|
        hiiro.add_subcmd(format.name, *format.aliases) { |*args| Codec.run(direction, format, args) }
      end
      hiiro.add_subcmd(:help) { puts Codec.help(direction) }
      hiiro.add_default { puts Codec.help(direction) }
    end

    def percent_encode(bytes)
      bytes.bytes.map do |byte|
        character = byte.chr
        character.match?(/[A-Za-z0-9._~-]/) ? character : format('%%%02X', byte)
      end.join
    end

    def percent_decode(bytes)
      raise ArgumentError, 'malformed percent escape' if bytes.match?(/%(?![0-9A-Fa-f]{2})/)

      bytes.gsub(/%([0-9A-Fa-f]{2})/) { Regexp.last_match(1).to_i(16).chr }
    end

    def compact_ascii(bytes) = bytes.gsub(/[[:space:]]/, '')

    def decode_base64(bytes, urlsafe:)
      encoded = compact_ascii(bytes)
      alphabet = urlsafe ? /\A[A-Za-z0-9_-]*={0,2}\z/ : %r{\A[A-Za-z0-9+/]*={0,2}\z}
      raise ArgumentError, 'invalid alphabet' unless encoded.match?(alphabet)
      raise ArgumentError, 'invalid length' if encoded.length % 4 == 1

      encoded += '=' * ((4 - encoded.length % 4) % 4)
      urlsafe ? Base64.urlsafe_decode64(encoded) : Base64.strict_decode64(encoded)
    end

    def decode_hex(bytes)
      encoded = compact_ascii(bytes)
      raise ArgumentError, 'non-hexadecimal character' unless encoded.match?(/\A[0-9A-Fa-f]*\z/)
      raise ArgumentError, 'odd number of digits' if encoded.length.odd?

      [encoded].pack('H*')
    end

    def decode_json(bytes)
      value = JSON.parse(bytes)
      raise ArgumentError, 'input is valid JSON, but is not a JSON string' unless value.is_a?(String)

      value
    end
  end
end
