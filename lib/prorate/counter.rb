module Prorate
  # The counter implements a rolling window throttling mechanism. At each call to incr(), the Redis time
  # is obtained. A counter then gets set at the key corresponding to the timestamp of the request, with a
  # granularity of a second. If requests are done continuously and in large volume, the counter will therefore
  # create one key for each second of the given rolling window size. he counters per second are set to auto-expire
  # after the window lapses. When incr() is performed, there is 
  class Counter
    def initialize(redis:, logger: NullLogger, id:, window_size:)
      @redis = redis
      @logger = logger
      @id = id
      @in_span_of_seconds = window_size.to_i.abs
    end
  
    # Increments the throttle counter for this identifier, and returns the total number of requests
    # performed so far within the given time span. The caller can then determine whether the request has
    # to be throttled or can be let through.
    def incr
      sec, _ = @redis.time # Use Redis time instead of the system timestamp, so that all the nodes are consistent
      ts = sec.to_i # All Redis results are strings
      k = key_for_ts(ts)
      # Do the Redis stuff in a transaction, and capture only the necessary values
      # (the result of MULTI is all the return values of each call in sequence)
      *_, done_last_second, _, counter_values = @redis.multi do |txn|
        # Increment the counter 
        txn.incr(k)
        txn.expire(k, @in_span_of_seconds)

        span_start = ts - @in_span_of_seconds
        span_end = ts + 1
        possible_keys = (span_start..span_end).map{|prev_time| key_for_ts(prev_time) }
        @logger.debug { "%s: Scanning %d possible keys" % [@id, possible_keys.length] }
        
        # Fetch all the counter values within the time window. Despite the fact that this
        # will return thousands of elements for large sliding window sizes, the values are
        # small and an MGET in Redis is pretty cheap, so perf should stay well within limits.
        txn.mget(*possible_keys)
      end

      # Sum all the values. The empty keys return nils from MGET, which become 0 on to_i casts.
      total_requests_during_period = counter_values.map(&:to_i).inject(&:+)
      @logger.debug { "%s: %d reqs total during the last %d seconds" % [@id, total_requests_during_period, @in_span_of_seconds] }
      
      total_requests_during_period
    end
  
    private

    def key_for_ts(ts)
      "th:%s:%d" % [@id, ts]
    end
  end
end
