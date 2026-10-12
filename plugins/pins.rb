#!/usr/bin/env ruby

module Pins
  def self.load(hiiro)
    attach_methods(hiiro)
    add_subcommands(hiiro)
  end

  def self.add_subcommands(hiiro)
    hiiro.add_subcmd(:pin) do |*args|
      pins = hiiro.pins

      case args
      in [] then pins.pins.each {|k,v| puts "#{k} => #{v.inspect}" }
      in ['all'] then pins.pins.each {|k,v| puts "#{k} => #{v.inspect}" }
      in ['get', name] then puts pins.get(name)
      in [name] then puts pins.get(name)
      in ['rm', name] then pins.remove(name); puts pins.pins
      in ['remove', name] then pins.remove(name); puts pins.pins
      in ['set', name, value] then pins.set(name, value)
      in [name, value] then pins.set(name, value)
      in [name, *values] then pins.set(name, values.join(' '))
      else
        puts "No matching pin subcommand for #{args.inspect}"
      end
    end
  end

  def self.attach_methods(hiiro)
    hiiro.instance_eval do
      def pins
        @pins ||= Pin.new(self)
      end
    end
  end

  class Pin
    attr_reader :hiiro

    def initialize(hiiro) = @hiiro = hiiro

    def get(name)
      key = find(name)
      Hiiro::PinRecord.find_key(hiiro.bin_name, key)&.value if key
    end

    def set(name, value)
      Hiiro::PinRecord.set(hiiro.bin_name, name, value)
      value
    end

    def search(partial)
      Hiiro::Matcher.by_prefix(pins.keys, partial)
    end

    def find(partial)
      search(partial).first&.item
    end

    def find_all(partial)
      search(partial).matches.map(&:item)
    end

    def remove(name)
      result = search(name)
      if result.ambiguous?
        puts "Unable to remove pin.  Multiple matches: #{result.matches.map(&:item).inspect}"
        return
      end

      key = result.match&.item
      Hiiro::PinRecord.remove(hiiro.bin_name, key)&.value if key
    end

    def pins
      Hiiro::PinRecord.for_command(hiiro.bin_name).each_with_object({}) { |row, values| values[row.key] = row.value }
    end
  end
end
