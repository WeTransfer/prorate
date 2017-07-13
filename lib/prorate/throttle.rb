require 'digest'

module Prorate
  class Throttle < Ks.strict(:name, :limit, :period, :block_for, :redis, :logger)
    def initialize(*)
      super
      @discriminators = [name.to_s]
      self.redis = NullPool.new(redis) unless redis.respond_to?(:with)
    end
    
    def <<(discriminator)
      @discriminators << discriminator
    end
    
    def throttle!
      discriminator = Digest::SHA1.hexdigest(Marshal.dump(@discriminators))
      identifier = [name, discriminator].join(':')
      
      redis.with do |r|
        #logger.info { "Checking throttle block %s" % name }
        #raise Throttled.new(block_for) if Prorate::BlockFor.blocked?(id: identifier, redis: r)

        logger.info { "Applying throttle counter %s" % name }
        # allowed request rate is limit per period
        allowed_req_rate = period / limit
        bucket_capacity = limit # how many tokens can be in the bucket
        leak_rate = period / limit # tokens per second; 
        weight = 1 # how many tokens each request is worth
        resp = r.evalsha('ac3eeb0e21c24a41442e44627ece11f182a1d382', [], [identifier, bucket_capacity, leak_rate, weight, block_for])

        #c = Prorate::Counter.new(redis: r, id: identifier, logger: logger, window_size: period)
        #after_increment = c.incr
        if resp != "OK"
          logger.warn { "Throttle %s exceeded limit of %d at %d" % [name, limit, after_increment] }
          #Prorate::BlockFor.block!(redis: r, id: identifier, duration: block_for)
          raise Throttled.new(resp)
        end
      end
    end
  end
end
