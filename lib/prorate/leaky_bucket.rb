module Prorate

  # This offers just the leaky bucket implementation with fill control, but without the timed lock.
  # It does not raise any exceptions, it just tracks the state of a leaky bucket in Redis.
  class LeakyBucket
    LUA_SCRIPT_CODE = File.read(File.join(__dir__, "leaky_bucket.lua"))
    LUA_SCRIPT_HASH = Digest::SHA1.hexdigest(LUA_SCRIPT_CODE)

    class BucketState < Struct.new(:level, :full)
      alias_method :full?, :full

      def to_f
        level.to_f
      end

      def to_i
        level.to_i
      end
    end

    def initialize(redis_key:, leak_rate:, bucket_ttl:, redis:, bucket_capacity:)
      @redis_key = redis_key
      @bucket_ttl = bucket_ttl
      @redis = NullPool.new(redis) unless redis.respond_to?(:with)
      @leak_rate = leak_rate.to_f
      @capacity = bucket_capacity.to_f
    end

    # Places `n` tokens in the bucket.
    #
    # @return [BucketState] the state of the bucket after the operation
    def put(n_tokens)
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
      "#{@redis_key}.leaky_bucket.bucket_level"
    end

    # Returns the Redis key under which the last updated time of the bucket gets stored.
    # Note that the key is not guaranteed to contain a value if the bucket has not been filled
    # up recently.
    #
    # @return [String]
    def last_updated_key
      "#{@redis_key}.leaky_bucket.last_updated"
    end

    private

    def run_lua_bucket_script(n_tokens)
      @redis.with do |r|
        begin
          # The script returns a tuple of "whole tokens, microtokens"
          # to be able to smuggle the float across (similar to Redis TIME command)
          level_str, is_full_int = r.evalsha(
            LUA_SCRIPT_HASH,
            keys: [leaky_bucket_key, last_updated_key], argv: [@leak_rate, @bucket_ttl, n_tokens, @capacity])
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
