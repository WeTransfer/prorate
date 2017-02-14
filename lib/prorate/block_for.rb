module Prorate
  module BlockFor
    def self.block!(redis:, id:, duration:)
      k = "bl:%s" % id
      redis.setex(k, duration.to_i, 1)
    end
  
    def self.blocked?(redis:, id:)
      k = "bl:%s" % id
      !!redis.get(k)
    end
  end
end
