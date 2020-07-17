# 0.7.0

* Add a naked `LeakyBucket` object which allows one to build sophisticated rate limiting relying
  on the Ruby side of things more. It has less features than the `Throttle` but can be used for more
  fine-graned control of the throttling. It also does not use exceptions for flow control.
  The `Throttle` object used them because it should make the code abort *loudly* if a throttle is hit, but
  when the objective is to measure instead a smaller, less opinionated module can be more useful.
* Refactor the internals of the Throttle class so that it uses a default Logger, and document the arguments.
* Use fractional time measurement from Redis in Lua code. For our throttle to be precise we cannot really
  limit ourselves to "anchored slots" on the start of a second, and we would be effectively doing that
  with our previous setup.
* Fix the `redis` gem deprecation warnings when using `exists` - we will now use `exists?` if available.
* Remove dependency on the `ks` gem as we can use vanilla Structs or classes instead.

# 0.6.0

* Add `Throttle#status` method for retrieving the status of a throttle without placing any tokens
  or raising any exceptions. This is useful for layered throttles.

# 0.5.0

* Allow setting the number of tokens to add to the bucket in `Throttle#throttle!` - this is useful because
  sometimes a request effectively uses N of some resource in one go, and should thus cause a throttle
  to fire without having to do repeated calls

# 0.4.0

* When raising a `Throttled` exception, add the name of the throttle to it. This is useful when multiple
  throttles are used together and one needs to find out which throttle has fired.
* Reformat code according to wetransfer_style and make it compulsory on CI

# 0.3.0

* Replace the Ruby implementation of the throttle with a Lua script which runs within Redis. This allows us
  to do atomic gets+sets very rapidly.

# 0.1.0

* Initial release of Prorate
