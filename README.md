# Prorate

Provides a low-level time-based throttle. Is mainly meant for situations where using something like Rack::Attack is not very
useful since you need access to more variables. Under the hood, this uses a Lua script that implements the
[Leaky Bucket](https://en.wikipedia.org/wiki/Leaky_bucket) algorithm in a single threaded and race condition safe way.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'prorate'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install prorate

## Usage

Within your Rails controller:

    t = Prorate::Throttle.new(redis: Redis.new, logger: Rails.logger,
        name: "throttle-login-email", limit: 20, period: 5.seconds)
    # Add all the parameters that function as a discriminator
    t << request.ip
    t << params.require(:email)
    # ...and call the throttle! method
    t.throttle! # Will raise a Prorate::Throttled exception if the limit has been reached

To capture that exception, in the controller

    rescue_from Prorate::Throttled do |e|
      response.set_header('Retry-In', e.retry_in_seconds.to_s)
      render nothing: true, status: 429
    end

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/WeTransfer/prorate.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

