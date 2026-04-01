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
    def tags=(v) ; self.tags_json = Hiiro::DB::JSON.dump(v); end

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

    def display_string(index = nil)
      num = index ? "#{(index + 1).to_s.rjust(3)}." : ""
      shorthand_str = shorthand ? " [#{shorthand}]" : ""
      desc_str = description.to_s.empty? ? "" : " - #{description}"
      link_tags = tags
      tags_str = link_tags.any? ? " \e[30;104m#{link_tags.join(' ')}\e[0m" : ""
      "#{num}#{shorthand_str} #{url}#{desc_str}#{tags_str}".strip
    end

    def to_h
      {
        'url'         => url,
        'description' => description,
        'shorthand'   => shorthand,
        'created_at'  => created_at
      }
    end
  end
end
