require "prorate/version"
require "redis"

module Prorate
  Dir.glob(__dir__ + '/prorate/**/*.rb').sort.each do |path|
    require path
  end
  # Your code goes here...
end
