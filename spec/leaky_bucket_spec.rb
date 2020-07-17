require 'spec_helper'
require 'securerandom'

describe Prorate::LeakyBucket do
  describe 'in a happy path' do
    # There is timing involved in Prorate, and some issues can be intermittent.
    # To make sure _both_ code and tests are resilient, we should run multiple iterations
    # of the test and do it in a reproducible way.
    # one of the ways to make it reproducible is to use random names which are reproduced
    # with the same RSpec seed
    randomness = Random.new(RSpec.configuration.seed)
    generate_random_bucket_name = -> {
      (1..32).map do
        # bytes 97 to 122 are printable lowercase a-z
        randomness.rand(97..122)
      end.pack("C*")
    }

    25.times do |n|
      it "on iteration #{n} accepts the number of tokens and returns the new bucket level" do
        bucket_name = generate_random_bucket_name.()
        r = Redis.new
        bucket = described_class.new(redis: r, redis_key: bucket_name, leak_rate: 0.8, bucket_capacity: 2)

        # Nothing should be written into Redis just when creating the object in Ruby
        expect(r.get(bucket.leaky_bucket_key)).to be_nil
        expect(r.get(bucket.last_updated_key)).to be_nil

        expect(bucket.state.to_f).to be_within(0.00001).of(0)

        # Since we haven't put in any tokens, asking for the levels should not have created
        # any Redis keys as we do not need them
        expect(r.get(bucket.leaky_bucket_key)).to be_nil
        expect(r.get(bucket.last_updated_key)).to be_nil

        sleep(0.2) # Bucket should stay empty and not go into negative
        expect(bucket.state.to_f).to be >= 0

        # We fill to capacity, and even given the precision constraints we should _first_ leak the
        # tokens and then fillup (so we should receive a value which is as close to 2 as feasible)
        bucket_state = bucket.put(5)
        expect(bucket_state).to be_full
        expect(bucket_state.level).to be_within(0.005).of(2)

        # Since we did put in tokens now the keys should have been created
        expect(r.get(bucket.leaky_bucket_key)).not_to be_nil
        expect(r.get(bucket.last_updated_key)).not_to be_nil

        sleep(0.5)
        bucket_state = bucket.state
        expect(bucket_state).not_to be_full
        expect(bucket_state.level).to be_within(0.01).of(2 - (0.8 * 0.5))

        # If we take out tokens ("put" with a negative value) we should ever only end up at 0
        bucket_state = bucket.put(-20)
        expect(bucket_state).not_to be_full
        expect(bucket_state.level).to be_within(0.1).of(0)

        # We need to make sure the keys which we set have a TTL and that the TTL
        # is reasonable. We cannot check whether the key has been expired or not because deletion in
        # Redis is somewhat best-effort - there is no guarantee that something will be deleted at
        # the given TTL, so testing for it is not very useful
        expect(r.ttl(bucket.leaky_bucket_key)).to be_within(0.5).of(4)
        expect(r.ttl(bucket.last_updated_key)).to be_within(0.5).of(4)
      end
    end
  end
end
