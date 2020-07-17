# Prorate

Provides a low-level time-based throttle. Is mainly meant for situations where
using something like Rack::Attack is not very useful since you need access to
more variables. Under the hood, this uses a Lua script that implements the
[Leaky Bucket](https://en.wikipedia.org/wiki/Leaky_bucket) algorithm in a single
threaded and race condition safe way.

[![Build Status](https://travis-ci.org/WeTransfer/prorate.svg?branch=master)](https://travis-ci.org/WeTransfer/prorate)
[![Gem Version](https://badge.fury.io/rb/prorate.svg)](https://badge.fury.io/rb/prorate)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'prorate'
```

And then execute:

```shell
bundle install
```

Or install it yourself as:

```shell
gem install prorate
```

## Usage

The simplest mode of operation is throttling an endpoint, using the throttler
before the action happens.

Within your Rails controller:

```ruby
t = Prorate::Throttle.new(
    redis: Redis.new,
    logger: Rails.logger,
    name: "throttle-login-email",
    limit: 20,
    period: 5.seconds
)
# Add all the parameters that function as a discriminator.
t << request.ip << params.require(:email)
# ...and call the throttle! method
t.throttle! # Will raise a Prorate::Throttled exception if the limit has been reached
#
# Your regular action happens after this point
```

To capture that exception, in the controller

```ruby
rescue_from Prorate::Throttled do |e|
  response.set_header('Retry-After', e.retry_in_seconds.to_s)
  render nothing: true, status: 429
end
```

### Throttling and checking status

More exquisite control can be achieved by combining throttling (see previous
step) and - in subsequent calls - checking the status of the throttle before
invoking the throttle. **When you call `throttle!`, you add tokens to the leaky bucket.**

Let's say you have an endpoint that not only needs throttling, but you want to
ban [credential stuffers](https://en.wikipedia.org/wiki/Credential_stuffing)
outright. This is a multi-step process:

1. Respond with a 429 if the discriminators of the request would land in an
  already blocking 'credential-stuffing'-throttle
1. Run your regular throttling
1. Perform your sign in action
1. If the sign in was unsuccessful, add the discriminators to the
  'credential-stuffing'-throttle

In your controller that would look like this:

```ruby
t = Prorate::Throttle.new(
    redis: Redis.new,
    logger: Rails.logger,
    name: "credential-stuffing",
    limit: 20,
    period: 20.minutes
)
# Add all the parameters that function as a discriminator.
t << request.ip
# And before anything else, check whether it is throttled
if t.status.throttled?
  response.set_header('Retry-After', t.status.remaining_throttle_seconds.to_s)
  render(nothing: true, status: 429) and return
end

# run your regular throttles for the endpoint
other_throttles.map(:throttle!)
# Perform your sign in logic..

user = YourSignInLogic.valid?(
  email: params[:email],
  password: params[:password]
)

# Add the request to the credential stuffing throttle if we didn't succeed
t.throttle! unless user

# the rest of your action
```

To capture that exception, in the controller

```ruby
rescue_from Prorate::Throttled do |e|
  response.set_header('Retry-After', e.retry_in_seconds.to_s)
  render nothing: true, status: 429
end
```

## Using just the leaky bucket

There is also an object for using the heart of Prorate (the leaky bucket) without blocking or exceptions. This is useful
if you want to implement a more generic rate limiting solution and customise it in a fancier way. The leaky bucket on
it's own provides the following conveniences only:

* Track the number of tokens added and the number of tokens that have leaked
* Tracks whether a specific token fillup has overflown the bucket. This is only tracked momentarily if the bucket is limited

Level and leak rate are computed and provided as Floats instead of Integers (in the Throttle class).
To use it, employ the `LeakyBucket` object:

```ruby
# The leak_rate is in tokens per second
leaky_bucket = Prorate::LeakyBucket.new(redis: Redis.new, redis_key_prefix: "user123", leak_rate: 0.8, bucket_capacity: 2)
leaky_bucket.state.level #=> will return 0.0
leaky_bucket.state.full? #=> will return "false"
state_after_add = leaky_bucket.put(2) #=> returns a State object_
state_after_add.full? #=> will return "true"
state_after_add.level #=> will return 2.0
```

## Why Lua?

Prorate is implementing throttling using the "Leaky Bucket" algorithm and is extensively described [here](https://github.com/WeTransfer/prorate/blob/master/lib/prorate/throttle.rb). The implementation is using a Lua script, because is the only language available which runs inside Redis. Thanks to the speed benefits of Redis, the Lua script will also benefits from running fast too.

Using a Lua script in Prorate helps us achieving:

- A guarantee that our script will run atomically.

  The script is evaluated as a single Redis command. This ensures that the commands in the Lua script, will never be interleaved with other commands. They will always execute together.

- Any usages of time will use the Redis time.

  Throttling requires a consistent and monotonic _time source_. The only monotonic and consistent time source which is usable in the context of Prorate, is the `TIME` result of Redis itself. We are throttling requests from different machines, which will invariably have clock drift between them. This way using the Redis server `TIME` helps achieve consistency.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/WeTransfer/prorate.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
