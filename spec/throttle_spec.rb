require 'spec_helper'

describe Prorate::Throttle do
  describe '#throttle!' do
    let(:throttle_name) { 'leecher-%s' % SecureRandom.hex(2) }
    it 'throttles and raises an exception' do
      r = Redis.new
      t = Prorate::Throttle.new(redis: r, logger: Prorate::NullLogger, limit: 2, period: 2, block_for: 5, name: throttle_name)
      t << 'request-id'
      t << 'user-id'

      t.throttle!
      t.throttle!
      expect {
        t.throttle!
      }.to raise_error(Prorate::Throttled)
    end
    
    it 'uses the given parameters to differentiate between users' do
      r = Redis.new
      4.times { |i|
        t = Prorate::Throttle.new(redis: r, logger: Prorate::NullLogger, limit: 3, period: 2, block_for: 2, name: throttle_name)
        t << i
        3.times { t.throttle! }
      }
    end

    it 'applies a long block, even if the rolling window for the throttle is shorter' do
      r = Redis.new
      # Exhaust the request limit
      t = Prorate::Throttle.new(redis: r, logger: Prorate::NullLogger, limit: 4, period: 1, block_for: 60, name: throttle_name)
      4.times do
        t.throttle!
      end

      expect {
        t.throttle!
      }.to raise_error(Prorate::Throttled)

      sleep 1.5 # The counters have expired and the rolling window has passed, but the block is still set

      expect {
        t.throttle!
      }.to raise_error(Prorate::Throttled)
    end

    it 'blocks for 1 second if the throttle is set, and then releases it' do
      r = Redis.new
      # Exhaust the request limit
      4.times do
        t = Prorate::Throttle.new(redis: r, logger: Prorate::NullLogger, limit: 4, period: 1, block_for: 2, name: throttle_name)
        t.throttle!
      end
      
      expect {
        t = Prorate::Throttle.new(redis: r, logger: Prorate::NullLogger, limit: 4, period: 1, block_for: 1, name: throttle_name)
        t.throttle!
      }.to raise_error(Prorate::Throttled)
      
      sleep 1.5
      
      t = Prorate::Throttle.new(redis: r, logger: Prorate::NullLogger, limit: 4, period: 1, block_for: 1, name: throttle_name)
      t.throttle!
    end
    
    it 'logs all the things' do
      buf = StringIO.new
      logger = Logger.new(buf)
      logger.level = 0
      r = Redis.new
      t = Prorate::Throttle.new(redis: r, logger: logger, limit: 64, period: 15, block_for: 30, name: throttle_name)
      32.times { t.throttle! }
      expect(buf.string).not_to be_empty
      expect(buf.string).to include('32 reqs total during the last 15 seconds')
    end
  end
end
