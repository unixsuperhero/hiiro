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
      in ['rm', name] then puts pins.remove_and_save(name)
      in ['remove', name] then puts pins.remove_and_save(name)
      in ['set', name, value] then pins.set_and_save(name, value)
      in [name, value] then pins.set_and_save(name, value)
      in [name, *values] then pins.set_and_save(name, values.join(' '))
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
      pins[find(name)]
    end

    def set(name, value)
      pins[name.to_s] = value
    end

    def set_and_save(name, value)
      set(name, value)
      save_pins
      value
    end

    def search(partial)
      Hiiro::Matcher.by_prefix(pins.keys.map(&:to_s), partial)
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

      pin_name = result.match&.item

      pins.delete(pin_name.to_s)
    end

    def remove_and_save(name)
      remove(name)
      save_pins
      pins
    end

    def pin_filename = hiiro.bin_name
    def pin_dir = Hiiro::Config.config_dir('pins').tap {|dir| FileUtils.mkdir_p(dir) }
    def pin_file = File.join(pin_dir, pin_filename)

    def load_pins_from_yaml
      return {} unless File.exist?(pin_file)
      YAML.safe_load_file(pin_file) || {}
    end

    def pins
      return @pins if @pins
      @pins = load_pins
      # Create YAML file on first access if absent (backward compatibility)
      File.write(pin_file, YAML.dump({}, stringify_names: true)) unless File.exist?(pin_file)
      @pins
    end

    def load_pins
      rows = Hiiro::PinRecord.for_command(pin_filename)
      rows.each_with_object({}) { |r, h| h[r.key] = r.value }
    rescue => e
      warn "Pin DB load failed: #{e}"
      load_pins_from_yaml
    end

    def save_pins(pins = nil)
      pins ||= @pins || {}
      current_keys = pins.keys.map(&:to_s)
      # Remove records no longer in pins (handles deletes)
      Hiiro::PinRecord.where(command: pin_filename).exclude(key: current_keys).delete
      pins.each do |key, value|
        existing = Hiiro::PinRecord.find_key(pin_filename, key)
        value_json = value.is_a?(String) ? value : Hiiro::DB::JSON.dump(value)
        if existing
          existing.update(value_json: value_json)
        else
          Hiiro::PinRecord.create(
            command: pin_filename,
            key: key.to_s,
            value_json: value_json
          )
        end
      end
      # Dual-write: rewrite per-command YAML file
      FileUtils.mkdir_p(pin_dir)
      File.write(pin_file, YAML.dump(pins, stringify_names: true))
    rescue => e
      warn "Pin DB save failed: #{e}"
    end

    def pins!
      @pins = nil
      pins
    end
  end
end
