require 'digest'

module Prorate
  class MisconfiguredThrottle < StandardError
  end

  class Throttle < Ks.strict(:name, :limit, :period, :block_for, :redis, :logger)
    LUA_SCRIPT_CODE = File.read(File.join(__dir__, "rate_limit.lua"))
    LUA_SCRIPT_HASH = Digest::SHA1.hexdigest(LUA_SCRIPT_CODE)

    def initialize(*)
      super
      @discriminators = [name.to_s]
      self.redis = NullPool.new(redis) unless redis.respond_to?(:with)
      raise MisconfiguredThrottle if (period <= 0) || (limit <= 0)
      @leak_rate = limit.to_f / period # tokens per second;
    end

    # Add a value that will be used to distinguish this throttle from others.
    # It has to be something user- or connection-specific, and multiple
    # discriminators can be combined:
    #
    #    throttle << ip_address << user_agent_fingerprint
    #
    # @param discriminator[Object] a Ruby object that can be marshaled
    #    in an equivalent way between requests, using `Marshal.dump
    def <<(discriminator)
      @discriminators << discriminator
    end

    # Applies the throttle and raises a {Throttled} exception if it has been triggered
    #
    # Accepts an optional number of tokens to put in the bucket (default is 1).
    # The effect of `n_tokens:` set to 0 is a "ping".
    # It makes sure the throttle keys in Redis get created and adjusts the
    # last invoked time of the leaky bucket. Can be used when a throttle
    # is applied in a "shadow" fashion. For example, imagine you
    # have a cascade of throttles with the following block times:
    #
    #   Throttle A: [-------]
    #   Throttle B: [----------]
    #
    # You apply Throttle A: and it fires, but when that happens you also
    # want to enable a throttle that is applied to "repeat offenders" only -
    # - for instance ones that probe for tokens and/or passwords.
    #
    #   Throttle C: [-------------------------------]
    #
    # If your "Throttle A" fires, you can trigger Throttle C
    #
    #    Throttle A: [-----|-]
    #    Throttle C: [-----|-------------------------]
    #
    # because you know that Throttle A has fired and thus Throttle C comes
    # into effect.  What you want to do, however, is to fire Throttle C
    # even though Throttle A: would have unlatched, which would create this
    # call sequence:
    #
    #    Throttle A: [-------]    *(A not triggered)
    #    Throttle C: [------------|------------------]
    #
    # To achieve that you can keep Throttle C alive using `throttle!(n_tokens: 0)`,
    # on every check that touches Throttle A and/or Throttle C. It keeps the leaky bucket
    # updated but does not add any tokens to it:
    #
    #    Throttle A: [------]    *(A not triggered since block period has ended)
    #    Throttle C: [-----------|(ping)------------------]  C is still blocking
    #
    # So you can effectively "keep a throttle alive" without ever triggering it,
    # or keep it alive in combination with other throttles.
    #
    # @param n_tokens[Integer] the number of tokens to put in the bucket. If you are
    #   using Prorate for rate limiting, and a single request is adding N objects to your
    #   database for example, you can "top up" the bucket with a set number of tokens
    #   with a arbitrary ratio - like 1 token per inserted row. Once the bucket fills up
    #   the Throttled exception is going to be raised. Defaults to 1.
    def throttle!(n_tokens: 1)
      discriminator = Digest::SHA1.hexdigest(Marshal.dump(@discriminators))
      identifier = [name, discriminator].join(':')

      redis.with do |r|
        logger.debug { "Applying throttle counter %s" % name }
        remaining_block_time, bucket_level = run_lua_throttler(
          redis: r,
          identifier: identifier,
          bucket_capacity: limit,
          leak_rate: @leak_rate,
          block_for: block_for,
          n_tokens: n_tokens)

        if remaining_block_time > 0
          logger.warn { "Throttle %s exceeded limit of %d in %d seconds and is blocked for the next %d seconds" % [name, limit, period, remaining_block_time] }
          raise ::Prorate::Throttled.new(name, remaining_block_time)
        end
        return limit - bucket_level # How many calls remain
      end
    end

    def throttled?
      discriminator = Digest::SHA1.hexdigest(Marshal.dump(@discriminators))
      identifier = [name, discriminator].join(':')

      redis.with do |r|
        r.exists("#{identifier}.block")
      end
    end

    def remaining_throttle_seconds
      discriminator = Digest::SHA1.hexdigest(Marshal.dump(@discriminators))
      identifier = [name, discriminator].join(':')

      redis.with do |r|
        remaining_seconds = r.get("#{identifier}.block").to_i
        return 0 unless remaining_seconds > 0

        remaining_seconds - Time.now.to_i
      end
    end

    private

    def run_lua_throttler(redis:, identifier:, bucket_capacity:, leak_rate:, block_for:, n_tokens:)
      redis.evalsha(LUA_SCRIPT_HASH, [], [identifier, bucket_capacity, leak_rate, block_for, n_tokens])
    rescue Redis::CommandError => e
      if e.message.include? "NOSCRIPT"
        # The Redis server has never seen this script before. Needs to run only once in the entire lifetime
        # of the Redis server, until the script changes - in which case it will be loaded under a different SHA
        redis.script(:load, LUA_SCRIPT_CODE)
        retry
      else
        raise e
      end
    end
  end
end
