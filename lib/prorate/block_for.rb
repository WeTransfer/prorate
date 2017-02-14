module Prorate
  module BlockFor
    def self.block!(redis:, id:, duration:)
      k = "bl:%s" % id
      redis.multi do |txn|
        txn.set(k, 1)
        txn.expire(k, duration.to_i)
      end
    end
  
    def self.blocked?(redis:, id:)
      k = "bl:%s" % id
      !!redis.get(k)
    end
  end
end
