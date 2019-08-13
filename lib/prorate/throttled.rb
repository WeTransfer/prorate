# The Throttled exception gets raised when a throttle is triggered.
#
# The exception carries additional attributes which can be used for
# error tracking and for creating a correct Retry-After HTTP header for
# a 429 response
class Prorate::Throttled < StandardError
  # @attr [String] the name of the throttle (like "shpongs-per-ip").
  #   Can be used to detect which throttle has fired when multiple
  #   throttles are used within the same block.
  attr_reader :throttle_name

  # @attr [Integer] for how long the caller will be blocked, in seconds.
  attr_reader :retry_in_seconds

  def initialize(throttle_name, try_again_in)
    @throttle_name = throttle_name
    @retry_in_seconds = try_again_in
    super("Throttled, please lower your temper and try again in #{retry_in_seconds} seconds")
  end
end
