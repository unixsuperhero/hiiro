class Hiiro
  # A link URL with {placeholder} slots and the values chosen for them.
  # Substitution only turns spaces into '+', as h-link always has.
  class URLTemplate
    PLACEHOLDER = /\{(\w+)\}/

    attr_reader :source_url, :values, :link

    def initialize(source_url, values: {}, link: nil)
      @source_url = source_url.to_s
      @values = values || {}
      @link = link
    end

    def placeholders   = source_url.scan(PLACEHOLDER).flatten
    def placeholders?  = !placeholders.empty?
    def missing_values = placeholders.reject { |name| values.key?(name) || values.key?(name.to_sym) }
    def complete?      = missing_values.empty?

    def url
      values.each_with_object(source_url.dup) do |(key, value), result|
        result.gsub!("{#{key}}", value.to_s.gsub(' ', '+'))
      end
    end
  end
end
