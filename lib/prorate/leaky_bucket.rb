module Prorate

  # This offers just the leaky bucket implementation with fill control, but without the timed lock.
  # It does not raise any exceptions, it just tracks the state of a leaky bucket in Redis.
  #
  # Important differences from the more full-featured Throttle class are:
  #
  # * No logging (as most meaningful code lives in Lua anyway)
  # * No timed block - if you need to keep track of timed blocking it can be done externally
  # * Leak rate is specified directly in tokens per second, instead of specifying the block period.
  # * The bucket level is stored and returned as a Float which allows for finer-grained measurement,
  #   but more importantly - makes testing from the outside easier.
  #
  # It does have a few downsides compared to the Throttle though
  #
  # * Bucket is only full momentarily. On subsequent calls some tokens will leak already, so you either
  #   need to do delta checks on the value or rely on putting the token into the bucket.
  class LeakyBucket
    LUA_SCRIPT_CODE = File.read(File.join(__dir__, "leaky_bucket.lua"))
    LUA_SCRIPT_HASH = Digest::SHA1.hexdigest(LUA_SCRIPT_CODE)

    class BucketState < Struct.new(:level, :full)
      # Returns the level of the bucket after the operation on the LeakyBucket
      # object has taken place. There is a guarantee that no tokens have leaked
      # from the bucket between the operation and the freezing of the BucketState
      # struct.
      #
      # @!attribute [r] level
      #   @return [Float]

      # Tells whether the bucket was detected to be full when the operation on
      # the LeakyBucket was performed. There is a guarantee that no tokens have leaked
      # from the bucket between the operation and the freezing of the BucketState
      # struct.
      #
      # @!attribute [r] full
      #   @return [Boolean]

      alias_method :full?, :full

      # Returns the bucket level of the bucket state as a Float
      #
      # @return [Float]
      def to_f
        level.to_f
      end

      # Returns the bucket level of the bucket state rounded to an Integer
      #
      # @return [Integer]
      def to_i
        level.to_i
      end
    end

    # Creates a new LeakyBucket. The object controls 2 keys in Redis: one
    # for the last access time, and one for the contents of the key.
    #
    # @param redis_key_prefix[String] the prefix that is going to be used for keys.
    #   If your bucket is specific to a user, a browser or an IP address you need to mix in
    #   those values into the key prefix as appropriate.
    # @param leak_rate[Float] the leak rate of the bucket, in tokens per second
    # @param redis[Redis,#with] a Redis connection or a ConnectionPool instance
    #   if you are using the connection_pool gem. With a connection pool Prorate will
    #   checkout a connection using `#with` and check it in when it's done.
    # @param bucket_capacity[Numeric] how many tokens is the bucket capped at.
    #   Filling up the bucket using `fillup()` will add to that number, but
    #   the bucket contents will then be capped at this value. So with
    #   bucket_capacity set to 12 and a `fillup(14)` the bucket will reach the level
    #   of 12, and will then immediately start leaking again.
    def initialize(redis_key_prefix:, leak_rate:, redis:, bucket_capacity:)
      @redis_key_prefix = redis_key_prefix
      @redis = NullPool.new(redis) unless redis.respond_to?(:with)
      @leak_rate = leak_rate.to_f
      @capacity = bucket_capacity.to_f
    end

    # Places `n` tokens in the bucket.
    #
    # @return [BucketState] the state of the bucket after the operation
    def fillup(n_tokens)
      run_lua_bucket_script(n_tokens.to_f)
    end

    # Returns the current state of the bucket, containing the level and whether the bucket is full
    #
    # @return [BucketState] the state of the bucket after the operation
    def state
      run_lua_bucket_script(0)
    end

    # Returns the Redis key for the leaky bucket itself
    # Note that the key is not guaranteed to contain a value if the bucket has not been filled
    # up recently.
    #
    # @return [String]
    def leaky_bucket_key
      "#{@redis_key_prefix}.leaky_bucket.bucket_level"
    end

    # Returns the Redis key under which the last updated time of the bucket gets stored.
    # Note that the key is not guaranteed to contain a value if the bucket has not been filled
    # up recently.
    #
    # @return [String]
    def last_updated_key
      "#{@redis_key_prefix}.leaky_bucket.last_updated"
    end

    private

    def run_lua_bucket_script(n_tokens)
      @redis.with do |r|
        begin
          # The script returns a tuple of "whole tokens, microtokens"
          # to be able to smuggle the float across (similar to Redis TIME command)
          level_str, is_full_int = r.evalsha(
            LUA_SCRIPT_HASH,
            keys: [leaky_bucket_key, last_updated_key], argv: [@leak_rate, n_tokens, @capacity])
          BucketState.new(level_str.to_f, is_full_int == 1)
        rescue Redis::CommandError => e
          if e.message.include? "NOSCRIPT"
            # The Redis server has never seen this script before. Needs to run only once in the entire lifetime
            # of the Redis server, until the script changes - in which case it will be loaded under a different SHA
            r.script(:load, LUA_SCRIPT_CODE)
            retry
          else
            raise e
          end
        end
      end
    end
  end
end
