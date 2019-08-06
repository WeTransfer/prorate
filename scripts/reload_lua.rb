# Reloads the script into redis and prints out the SHA it can be called with
require 'redis'
r = Redis.new
script = File.read('../lib/prorate/rate_limit.lua')
sha = r.script(:load, script)
puts sha
