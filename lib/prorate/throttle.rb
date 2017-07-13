require 'digest'

module Prorate
  class Throttled < StandardError
  end

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
        logger.info { "Applying throttle counter %s" % name }
        allowed_req_rate = period / limit
        bucket_capacity = limit # how many tokens can be in the bucket
        leak_rate = period / limit # tokens per second; 
        # weight = 1 # how many tokens each request is worth
        resp = run_lua_throttler(redis: r, identifier: identifier, bucket_capacity: bucket_capacity, leak_rate: leak_rate, weight: 1, block_for)

        if resp != "OK"
          logger.warn { "Throttle %s exceeded limit of %d at %d" % [name, limit, after_increment] }
          raise Throttled.new("Throttled, please lower your temper and try again in #{resp} seconds")
        end
      end
    end

    def run_lua_throttler(redis: , identifier: , bucket_capacity: , leak_rate: , weight: , block_for)
      # Slightly magic hash:
      redis.evalsha('ac3eeb0e21c24a41442e44627ece11f182a1d382', [], [identifier, bucket_capacity, leak_rate, weight, block_for])
    rescue Redis::CommandError => e
      if e.message.include? "NOSCRIPT"
        # The Redis server has never seen this script before. Needs to run only once in the entire lifetime of the server (unless the script changes)
        script_filepath = File.join(__dir__,"rate_limit.lua")
        script = File.read(script_filepath)
        redis.script(:load, script)
        redis.evalsha('ac3eeb0e21c24a41442e44627ece11f182a1d382', [], [identifier, bucket_capacity, leak_rate, weight, block_for])
      end
    end
  end
end
