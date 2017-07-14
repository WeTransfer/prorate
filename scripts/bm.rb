# Runs a mild benchmark and prints out the average time a call to 'throttle!' takes.

require 'prorate'
require 'benchmark'
require 'redis'
require 'securerandom'

def average_ms(ary)
  ary.map{|x| x*1000}.inject(0,&:+) / ary.length
end

r = Redis.new

logz = Logger.new(STDERR)
logz.level = Logger::FATAL # block out most stuff

times = []
15.times do
  times << Benchmark.realtime {
    t = Prorate::Throttle.new(redis: r, logger: logz, name: "throttle-login-email", limit: 60, period: 120, block_for: 5)
    # Add all the parameters that function as a discriminator
    t << '127.0.2.1'
    t << 'no_person@nowhere.com'
    t.throttle!
  }
end

puts average_ms times

times = []
15.times do
  email = SecureRandom.hex(20)
  ip = SecureRandom.hex(10)
  times << Benchmark.realtime {
    t = Prorate::Throttle.new(redis: r, logger: logz, name: "throttle-login-email", limit: 20, period: 120, block_for: 5)
    # Add all the parameters that function as a discriminator
    t << ip
    t << email
    t.throttle!
  }
end

puts average_ms times
