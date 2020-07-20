require 'digest'

module Prorate
  class MisconfiguredThrottle < StandardError
  end

  class Throttle
    LUA_SCRIPT_CODE = File.read(File.join(__dir__, "rate_limit.lua"))
    LUA_SCRIPT_HASH = Digest::SHA1.hexdigest(LUA_SCRIPT_CODE)

    attr_reader :name, :limit, :period, :block_for, :redis, :logger

    def initialize(name:, limit:, period:, block_for:, redis:, logger: Prorate::NullLogger)
      @name = name.to_s
      @discriminators = [name.to_s]
      @redis = redis.respond_to?(:with) ? redis : NullPool.new(redis)
      @logger = logger
      @block_for = block_for

      raise MisconfiguredThrottle if (period <= 0) || (limit <= 0)

      # Do not do type conversions here since we want to allow the caller to read
      # those values back later
      # (API contract which the previous implementation of Throttle already supported)
      @limit = limit
      @period = period

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
      @logger.debug { "Applying throttle counter %s" % @name }
      remaining_block_time, bucket_level = run_lua_throttler(
        identifier: identifier,
        bucket_capacity: @limit,
        leak_rate: @leak_rate,
        block_for: @block_for,
        n_tokens: n_tokens)

      if remaining_block_time > 0
        @logger.warn do
          "Throttle %s exceeded limit of %d in %d seconds and is blocked for the next %d seconds" % [@name, @limit, @period, remaining_block_time]
        end
        raise ::Prorate::Throttled.new(@name, remaining_block_time)
      end

      @limit - bucket_level # Return how many calls remain
    end

    def status
      redis_block_key = "#{identifier}.block"
      @redis.with do |r|
        is_blocked = redis_key_exists?(r, redis_block_key)
        if is_blocked
          remaining_seconds = r.get(redis_block_key).to_i - Time.now.to_i
          Status.new(_is_throttled = true, remaining_seconds)
        else
          remaining_seconds = 0
          Status.new(_is_throttled = false, remaining_seconds)
        end
      end
    end

    private

    def identifier
      discriminator = Digest::SHA1.hexdigest(Marshal.dump(@discriminators))
      "#{@name}:#{discriminator}"
    end

    # redis-rb 4.2 started printing a warning for every single-argument use of `#exists`, because
    # they intend to break compatibility in a future version (to return an integer instead of a
    # boolean). The old behavior (returning a boolean) is available using the new `exists?` method.
    def redis_key_exists?(redis, key)
      return redis.exists?(key) if redis.respond_to?(:exists?)
      redis.exists(key)
    end

    def run_lua_throttler(identifier:, bucket_capacity:, leak_rate:, block_for:, n_tokens:)
      @redis.with do |redis|
        begin
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

    class Status < Struct.new(:is_throttled, :remaining_throttle_seconds)
      def throttled?
        is_throttled
      end
    end
  end
end
