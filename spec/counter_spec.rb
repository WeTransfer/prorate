require 'spec_helper'

describe Prorate::Counter do

  it 'records request counters, triggered from threads' do
    id = "User %s" % SecureRandom.hex(4)

    hammer_threads = (1..4).map do
      Thread.new do
        r = Redis.new
        counter = Prorate::Counter.new(redis: r, id: id, window_size: 120)
        32.times do
          sleep(rand / 3.0)
          counter.incr
        end
      end
    end
    hammer_threads.map(&:join)
    
    r = Redis.new
    counter = Prorate::Counter.new(redis: r, id: id, window_size: 120)
    last_value = counter.incr
    expect(last_value).to eq((4 * 32) + 1)
  end
  
  it 'only stores the request count for the given interval' do
    r = Redis.new
    id = "User %s" % SecureRandom.hex(4)
    4.times do
      counter = Prorate::Counter.new(redis: r, id: id, window_size: 2)
      counter.incr
      sleep 1
    end
    
    counter = Prorate::Counter.new(redis: r, id: id, window_size: 2)
    expect(counter.incr).to eq(2)
  end

  it 'stores all the requests performed during two bursts' do
    r = Redis.new
    id = "User %s" % SecureRandom.hex(4)
    2.times do
      sleep 0.7
      1000.times {
        counter = Prorate::Counter.new(redis: r, id: id, window_size: 3)
        counter.incr
      }
    end
    
    counter = Prorate::Counter.new(redis: r, id: id, window_size: 3)
    expect(counter.incr).to eq(2001)
  end
end
