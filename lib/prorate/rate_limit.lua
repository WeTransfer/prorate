-- Single threaded Leaky Bucket implementation.
-- args: key_base, leak_rate, max_bucket_capacity, block_duration
-- returns: an array of two integers, the first of which indicates the remaining block time.
-- if the block time is nonzero, the second integer is always zero. If the block time is zero,
-- the second integer indicates the level of the bucket

-- this is required to be able to use TIME and writes; basically it lifts the script into IO
redis.replicate_commands()
-- make some nicer looking variable names:
local retval = nil
local bucket_level_key = ARGV[1] .. ".bucket_level"
local last_updated_key = ARGV[1] .. ".last_updated"
local block_key = ARGV[1] .. ".block"
local max_bucket_capacity = tonumber(ARGV[2])
local leak_rate = tonumber(ARGV[3])
local block_duration = tonumber(ARGV[4])
local now = tonumber(redis.call("TIME")[1]) --unix timestamp, will be required in all paths

local key_lifetime = math.ceil(max_bucket_capacity / leak_rate)

local blocked_until = redis.call("GET", block_key)
if blocked_until then
  return {(tonumber(blocked_until) - now), 0}
end

-- get current bucket level
local bucket_level = tonumber(redis.call("GET", bucket_level_key))
if not bucket_level then
  -- this throttle/identifier combo does not exist yet, so much calculation can be skipped
  redis.call("SETEX", bucket_level_key, key_lifetime, 1) -- set bucket with initial value
  retval =  {0, 1}
else
  -- if it already exists, do the leaky bucket thing
  local last_updated = tonumber(redis.call("GET", last_updated_key)) or now -- use sensible default of 'now' if the key does not exist
  local new_bucket_level = math.max(0, bucket_level - (leak_rate * (now - last_updated)))

  if (new_bucket_level + 1) <= max_bucket_capacity then
    new_bucket_level = new_bucket_level + 1
    retval = {0, math.ceil(new_bucket_level)}
  else
    redis.call("SETEX", block_key, block_duration, now + block_duration)
    retval = {block_duration, 0}
  end
  redis.call("SETEX", bucket_level_key, key_lifetime, new_bucket_level) --still needs to be saved
end

-- update last_updated for this bucket, required in all branches
redis.call("SETEX", last_updated_key, key_lifetime, now)

return retval
