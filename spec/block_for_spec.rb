require 'spec_helper'

describe Prorate::BlockFor do

  it 'records the block' do
    r = Redis.new
    id = "random-block-id-%s" % SecureRandom.hex(2)
    expect(Prorate::BlockFor).not_to be_blocked(redis: r, id: id)

    Prorate::BlockFor.block!(redis: r, id: id, duration: 10)

    expect(Prorate::BlockFor).to be_blocked(redis: r, id: id)
  end
end
