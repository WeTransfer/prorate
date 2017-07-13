-- Single threaded Leaky Bucket implementation.
-- args: key_base, leak_rate, max_bucket_capacity, weight, 

-- this is required to be able to use TIME and writes; basically it lifts the script into IO
redis.replicate_commands()
-- make some nicer looking variable names:
local retval = nil
local bucket_key = ARGV[1] .. ".value"
local last_updated_key = ARGV[1] .. ".last_update"
local max_bucket_capacity = tonumber(ARGV[2])
local leak_rate = tonumber(ARGV[3])
local weight = tonumber(ARGV[4])
local now = tonumber(redis.call("TIME")[1]) --unix timestamp, will be required in all paths

-- get current bucket level
local count = tonumber(redis.call("GET", bucket_key))
--exit early if this does not exist yet
if count == nil then
  --exit early because this throttle/identifier combo does not exist yet
  redis.call("SET", bucket_key, weight) -- set bucket with initial value
  retval =  "OK"
else
  -- if it already exists, do the leaky bucket thing
  local last_updated = tonumber(redis.call("GET", last_updated_key))
  local new_count = math.max(0, count - (leak_rate * ((now - last_updated))))

  if weight <= (max_bucket_capacity - new_count) then
    new_count = new_count + weight
    retval =  "OK"
  else
    retval =  "NOK"
  end
  redis.call("SET", bucket_key, new_count) --still needs to be saved
end

-- update last_updated for this bucket, required in all branches
redis.call("SET", last_updated_key, now)

--expiring keys is always required
local key_lifetime = math.ceil(max_bucket_capacity / leak_rate)
redis.call("EXPIRE", bucket_key, key_lifetime)
redis.call("EXPIRE", last_updated_key, key_lifetime)

return retval
