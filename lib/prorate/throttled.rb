module Prorate
  class Throttled < StandardError
    attr_reader :retry_in_seconds
    def initialize(try_again_in)
      @retry_in_seconds = try_again_in
      super("Throttled, please lower your temper and try again in %d seconds" % try_again_in)
    end
  end
end
