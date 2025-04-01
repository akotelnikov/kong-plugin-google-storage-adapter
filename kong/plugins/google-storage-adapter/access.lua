local auth = require "kong.plugins.google-storage-adapter.auth"
local path = require "kong.plugins.google-storage-adapter.path"
local headers = require "kong.plugins.google-storage-adapter.headers"

local _M = {}

function _M.execute(conf)
  auth.do_authentication(conf)
  path.transform_uri(conf)
  headers.add_service_headers(conf)
end

return _M
