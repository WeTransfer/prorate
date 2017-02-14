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
        logger.info { "Checking throttle block %s" % name }
        raise Throttled.new(block_for) if Prorate::BlockFor.blocked?(id: identifier, redis: r)

        logger.info { "Applying throttle counter %s" % name }
        c = Prorate::Counter.new(redis: r, id: identifier, logger: logger, window_size: period)
        after_increment = c.incr
        if after_increment > limit
          logger.warn { "Throttle %s exceeded limit of %d at %d" % [name, limit, after_increment] }
          Prorate::BlockFor.block!(redis: r, id: identifier, duration: block_for)
          raise Throttled.new(period)
        end
      end
    end
  end
end
