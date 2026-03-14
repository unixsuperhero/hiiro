class Hiiro
  module AnyStruct
    attr_reader :_args, :_raw_data

    def initialize(*args, **raw_data)
      @_args = args
      @_raw_data = raw_data

      hashes = args.select{|arg| arg.is_a?(Hash) }.each
      init_data(*hashes, raw_data)
    end

    private def init_data(*hashes)
      hashes.each do |h|
        h.each do |key, value|
          instance_variable_set(:"@#{key}", value)

          define_singleton_method(key) do
            instance_variable_get(:"@#{key}")
          end

          define_singleton_method(:"#{key}=") do |val|
            instance_variable_set(:"@#{key}", val)
          end
        end
      end
    end
  end
end
