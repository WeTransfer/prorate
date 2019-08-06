# Runs a mild benchmark and prints out the average time a call to 'throttle!' takes.

require 'prorate'
require 'benchmark'
require 'redis'
require 'securerandom'

def average_ms(ary)
  ary.map { |x| x * 1000 }.inject(0, &:+) / ary.length
end

r = Redis.new

# 4000000.times do
#   random1 = SecureRandom.hex(10)
#   random2 = SecureRandom.hex(10)
#   r.set(random1,random2)
# end

logz = Logger.new(STDERR)
logz.level = Logger::FATAL # block out most stuff

times = []
15.times do
  id = SecureRandom.hex(10)
  times << Benchmark.realtime {
    r.evalsha('c95c5f1197cef04ec4afd7d64760f9175933e55a', [], [id, 120, 50, 10]) # values beyond 120 chosen more or less at random
  }
end

puts average_ms times
def key_for_ts(ts)
  "th:%s:%d" % [@id, ts]
end

times = []
15.times do
  sec, _ = r.time # Use Redis time instead of the system timestamp, so that all the nodes are consistent
  ts = sec.to_i # All Redis results are strings
  k = key_for_ts(ts)
  times << Benchmark.realtime {
    r.multi do |txn|
      # Increment the counter
      txn.incr(k)
      txn.expire(k, 120)

      span_start = ts - 120
      span_end = ts + 1
      possible_keys = (span_start..span_end).map { |prev_time| key_for_ts(prev_time) }

      # Fetch all the counter values within the time window. Despite the fact that this
      # will return thousands of elements for large sliding window sizes, the values are
      # small and an MGET in Redis is pretty cheap, so perf should stay well within limits.
      txn.mget(*possible_keys)
    end
  }
end

puts average_ms times
