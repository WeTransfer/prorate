require 'digest'

module Prorate
  class Throttled < StandardError
    attr_reader :retry_in_seconds
    def initialize(try_again_in)
      @retry_in_seconds = try_again_in
      super("Throttled, please lower your temper and try again in #{retry_in_seconds} seconds")
    end
  end

  class ScriptHashMismatch < StandardError
  end

  class MisconfiguredThrottle < StandardError
  end

  class Throttle < Ks.strict(:name, :limit, :period, :block_for, :redis, :logger)

    def self.get_script_hash
      script_filepath = File.join(__dir__,"rate_limit.lua")
      script = File.read(script_filepath)
      Digest::SHA1.hexdigest(script)
    end

    CURRENT_SCRIPT_HASH = get_script_hash

    def initialize(*)
      super
      @discriminators = [name.to_s]
      self.redis = NullPool.new(redis) unless redis.respond_to?(:with)
      raise MisconfiguredThrottle if ((period <= 0) || (limit <= 0))
      @leak_rate = limit.to_f / period # tokens per second;
    end
    
    def <<(discriminator)
      @discriminators << discriminator
    end
    
    def throttle!
      discriminator = Digest::SHA1.hexdigest(Marshal.dump(@discriminators))
      identifier = [name, discriminator].join(':')
      
      redis.with do |r|
        logger.info { "Applying throttle counter %s" % name }
        remaining_block_time, bucket_level = run_lua_throttler(redis: r, identifier: identifier, bucket_capacity: limit, leak_rate: @leak_rate, block_for: block_for)

        if remaining_block_time > 0
          logger.warn { "Throttle %s exceeded limit of %d in %d seconds and is blocked for the next %d seconds" % [name, limit, period, remaining_block_time] }
          raise Throttled.new(remaining_block_time)
        end
        available_calls = limit - bucket_level
      end
    end

    def run_lua_throttler(redis: , identifier: , bucket_capacity: , leak_rate: , block_for: )
      redis.evalsha(CURRENT_SCRIPT_HASH, [], [identifier, bucket_capacity, leak_rate, block_for])
    rescue Redis::CommandError => e
      if e.message.include? "NOSCRIPT"
        # The Redis server has never seen this script before. Needs to run only once in the entire lifetime of the Redis server (unless the script changes)
        script_filepath = File.join(__dir__,"rate_limit.lua")
        script = File.read(script_filepath)
        raise ScriptHashMismatch if Digest::SHA1.hexdigest(script) != CURRENT_SCRIPT_HASH
        redis.script(:load, script)
        redis.evalsha(CURRENT_SCRIPT_HASH, [], [identifier, bucket_capacity, leak_rate, block_for])
      else
        raise e
      end
    end
  end
end
