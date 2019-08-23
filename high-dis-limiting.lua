-- 20190820
---@type function json插件
local cjson = require("cjson")
---@type function http插件
local http = require("resty.http")
---@type function redis插件
local redis = require "resty.redis"


function getRedis()
    local red = redis:new()
    red:set_timeout(1000)
    local ok, err = red:connect("10.10.220.63", 6379)
    if not ok then
        ngx.log(ngx.INFO,err)
        return
    else
        ngx.log(ngx.INFO,"redis connect success")
        return red
    end
end

--获取redis
local red = getRedis()
function close_redis(red)
    if not red then
        return
    end
    --释放连接(连接池实现)
    local pool_max_idle_time = 10000 --毫秒
    local pool_size = 100 --连接池大小
    local ok, err = red:set_keepalive(pool_max_idle_time, pool_size)

    if not ok then
        ngx_log(ngx_ERR, "set redis keepalive error : ", err)
    end
end

--获取redis的key
function getKey(key,rate)
local resultKey="ratelimit:"..key..":oneqps:"..rate
return resultKey
end

local uri = ngx.var.request_uri -- 获取当前请求的uri

--local path=uri.sub(uri,uri.find("/"))
--ngx.log(ngx.INFO,"request_uri:"..uri)
local descIndex=string.find(string.reverse(uri),"/")
local sub_uri=string.sub(uri,1,string.len(uri)-descIndex)
--ngx.log(ngx.INFO,"sub_uri:"..sub_uri)
local testKey=getKey(sub_uri,100)
---刷新每个接口的限流信息
function refresh()
 local ok, err=red:incrby(testKey,3)
 if not ok then
    ngx.log(ngx.INFO, err)
  return
 end
 red:pexpire(testKey,5000)
 red:set(testKey..":last",os.time())
 red:pexpire(testKey..":last",10000)
 ngx.log(ngx.INFO,"refresh.......")
end


function result(resultCode)
--503
 ngx.status = ngx.HTTP_SERVICE_UNAVAILABLE 
 ngx.say(resultCode)
 ngx.exit(resultCode)
end

local res,err=red:get(testKey)
if not res then
    ngx.say("failed to get key: ", err)
    return
end
if res == ngx.null then 
   refresh()
   return
else
     
    local lastTime=red:get(testKey..":last")
    local currentTime=os.time()
    local lastToken=red:Decr(testKey)
    ngx.log(ngx.INFO, "before...currentTime:"..currentTime..",lastTime:"..lastTime..",lastToken:"..lastToken) 
    local flag=tonumber(lastToken) <= 0
    if tonumber(currentTime) <= tonumber(lastTime) and flag then
        ngx.log(ngx.INFO,"result:"..5000000003)
        result(503)
        return
    end
    if tonumber(currentTime) > tonumber(lastTime) then
       refresh()
       return
    end

    ngx.log(ngx.INFO,"end...currentTime:"..currentTime..",lastTime:"..lastTime..",current:"..res..",lastToken:"..lastToken)
end
