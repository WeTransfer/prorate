module Prorate
  class NullPool < Struct.new(:conn)
    def with
      yield conn
    end
  end
end
