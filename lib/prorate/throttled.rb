class Prorate::Throttled < StandardError
  attr_reader :throttle_name, :retry_in_seconds
  def initialize(throttle_name, try_again_in)
    @throttle_name = throttle_name
    @retry_in_seconds = try_again_in
    super("Throttled, please lower your temper and try again in #{retry_in_seconds} seconds")
  end
end
