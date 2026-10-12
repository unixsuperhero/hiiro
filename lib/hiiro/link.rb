require 'sequel'

class Hiiro
  class Link < Sequel::Model(:links)
    Hiiro::DB.register(self)

    def self.create_table!(db)
      db.create_table?(:links) do
        primary_key :id
        String :url, null: false, unique: true
        String :description
        String :shorthand
        String :tags_json   # JSON array of tag strings
        String :created_at
      end
    end

    def tags     = Hiiro::Tag.for(self).map(&:name)

    def self.remove(id)
      db.transaction(mode: :immediate) do
        link = self[id]
        next unless link
        Hiiro::Tag.for(link).delete
        link.destroy
      end
    end

    def self.find_by_shorthand(s)
      where(shorthand: s).first
    end

    def self.search(query)
      q = "%#{query}%"
      where(
        Sequel.|(
          Sequel.like(:url, q),
          Sequel.like(:description, q),
          Sequel.like(:shorthand, q)
        )
      ).order(:created_at).all
    end

    def self.ordered = order(:created_at).all

    def matches?(*terms)
      searchable = [url, description, shorthand].compact.join(' ').downcase
      terms.all? { |term| searchable.include?(term.downcase) }
    end

    def display_string(index = nil, exclude_tags: [])
      num = index ? "#{(index + 1).to_s.rjust(3)}." : ""
      shorthand_str = shorthand ? " [#{shorthand}]" : ""
      desc_str = description.to_s.empty? ? "" : " - #{description}"
      link_tags = tags - Array(exclude_tags)
      tags_str = link_tags.any? ? " " + link_tags.map { |t| "\e[30;104m#{t}\e[0m" }.join(' ') : ""
      "#{num}#{shorthand_str} #{url}#{desc_str}#{tags_str}".strip
    end

    def to_h
      {
        'id'          => id,
        'url'         => url,
        'description' => description,
        'shorthand'   => shorthand,
        'created_at'  => created_at
      }
    end
  end

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
