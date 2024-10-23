local access = require "kong.plugins.google-storage-adapter.access"

local GoogleStorageAdapterHandler = {
  VERSION = "1.8.0",
  PRIORITY = 901,
}

function GoogleStorageAdapterHandler:access(conf)
  access.execute(conf)
end

return GoogleStorageAdapterHandler