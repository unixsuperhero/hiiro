class Hiiro
  class AnyStruct
    def self.recursive_new(*args, **raw_data)
      args.push(raw_data).select { |arg|
        arg.is_a?(Hash)
      }.inject(:merge)
    end

    attr_reader :_raw_data

    def initialize(*args, **raw_data)
      hashes = args.select{|arg| arg.is_a?(Hash) }.inject(:merge)
      @_raw_data = hashes.merge(raw_data)
      @_raw_data.each { |k,v| set(k, v) }
    end

    def set(key, value)
      _raw_data[key.to_sym] = value

      define_singleton_method(key.to_sym) do
        _raw_data[key.to_sym]
      end
    end

    def get(key)
      _raw_data[key.to_sym]
    end
  end
end
