local uuid = require "resty.jit-uuid"
local openssl_hmac = require "resty.openssl.hmac"
local sha256 = require "resty.sha256"
local str = require "resty.string"

local kong = kong

local GCLOUD_STORAGE_HOST = "storage.googleapis.com"
local GCLOUD_METHOD = 'GET'
local GCLOUD_SIGNING_ALGORITHM = 'GOOG4-HMAC-SHA256'
local GCLOUD_REGION = "auto"
local GCLOUD_SERVICE = 'storage'
local GCLOUD_REQUEST_TYPE = 'goog4_request'
local GCLOUD_SIGNED_HEADERS = 'host;x-goog-content-sha256;x-goog-date'
local GCLOUD_UNSIGNED_PAYLOAD = 'UNSIGNED-PAYLOAD'

local _M = {}

local function get_service_path()
  local service = kong.router.get_service()
  if service then
    -- For example "/my-game/"
    return service.path
  end
  return ""
end

-- handle case when we have a trailing slash in the end of the path
local function add_index_file_to_path(req_path)
  if string.match(req_path, "(.*)/$") then
    return req_path .. "index.html"
  elseif string.match(req_path, "(.*)/[^/.]+$") then
    return req_path .. "/index.html"
  end
  return req_path
end

---
-- Constructs a normal req path to an exact resourse
--
-- Example:
-- /my-page -> /my-page/index.html
-- /my-page/ -> /my-page/index.html
-- /multipage/ru-RU/first-game-subpath/index.html -> /first-game/ru-RU/index.html
--
local function get_normalized_path(conf)
  local service_path = get_service_path()
  -- if there's any override to a particular page (e.g. 403.html)
  if string.match(service_path, "(.*).html$") then
    return service_path
  end

  local req_path = kong.request.get_path()

  -- if there's an active experiment we will change the service path
  local ab_testing_path = kong.ctx.shared.ab_testing_path
  if ab_testing_path and ab_testing_path ~= "" then
    local log_message = string.format(
    "An active A/B test has been found, the service request path will be changed to %s", ab_testing_path)
    kong.log.notice(log_message)
    req_path = ab_testing_path
  end

  -- by default we have the /sites prefix
  local prefix = conf.path_transformation.prefix
  if prefix then
    req_path = string.gsub(req_path, prefix, "")
  end

  if not conf.path_transformation.enabled then
    return req_path
  end

  -- multipage routes handling
  local main_domain = req_path:match("^/[a-zA-Z0-9%-%_]+/?") or ""
  local locale = req_path:match("%l%l%-%u%u/?") or ""
  local file_name = req_path:match("[a-zA-Z0-9-_]*%.?[a-zA-Z0-9-_]+%.[a-zA-Z0-9-_]+$") or ""
  local one_page_path = main_domain .. locale .. file_name
  local is_one_page_site = one_page_path == req_path

  if conf.path_transformation.log then
    local log_message = string.format(
      "The request path has been parsed successfully; The main domain is %s, the locale is %s, the file name is %s",
      main_domain, locale, file_name)
    kong.log.notice(log_message)
  end

  if is_one_page_site then
    return add_index_file_to_path(req_path)
  else
    local full_path = service_path .. locale .. file_name
    return add_index_file_to_path(full_path)
  end
end

local function create_canonical_request(conf, current_precise_date)
  local path = get_normalized_path(conf)

  local bucket_name = conf.request_authentication.bucket_name
  local host = bucket_name .. "." .. GCLOUD_STORAGE_HOST

  local canonical_uri = path
  local canonical_headers = 'host:' .. host .. "\n" ..
      'x-goog-content-sha256:' .. GCLOUD_UNSIGNED_PAYLOAD .. "\n" ..
      'x-goog-date:' .. current_precise_date

  local canonical_request = GCLOUD_METHOD .. "\n" ..
      canonical_uri .. "\n\n" ..
      canonical_headers .. '\n\n' ..
      GCLOUD_SIGNED_HEADERS .. "\n" ..
      GCLOUD_UNSIGNED_PAYLOAD

  return canonical_request
end

local function create_hex_canonical_request(canonical_request)
  local digest = sha256:new()
  digest:update(canonical_request)
  local canonical_request_hex = str.to_hex(digest:final())
  return canonical_request_hex
end

local function create_signing_key(secret, current_date)
  local secret = "GOOG4" .. secret
  local key_date = openssl_hmac.new(secret, "sha256"):final(current_date)
  local key_region = openssl_hmac.new(key_date, "sha256"):final(GCLOUD_REGION)
  local key_service = openssl_hmac.new(key_region, "sha256"):final(GCLOUD_SERVICE)
  local signing_key = openssl_hmac.new(key_service, "sha256"):final(GCLOUD_REQUEST_TYPE)
  return signing_key
end

-- implementation from https://cloud.google.com/storage/docs/authentication/signatures
local function do_authentication(conf)
  if not conf.request_authentication.enabled then
    return
  end

  local current_date = os.date("%Y%m%d")                 -- YYYYMMDD
  local current_precise_date = os.date("%Y%m%dT%H%M%SZ") -- YYYYMMDD'T'HHMMSS'Z'

  local credential_scope = current_date .. "/" .. GCLOUD_REGION .. "/" .. GCLOUD_SERVICE .. "/" .. GCLOUD_REQUEST_TYPE

  local canonical_request = create_canonical_request(conf, current_precise_date)
  local canonical_request_hex = create_hex_canonical_request(canonical_request)
  local string_to_sign = GCLOUD_SIGNING_ALGORITHM .. "\n" ..
      current_precise_date .. "\n" ..
      credential_scope .. "\n" ..
      canonical_request_hex

  local signing_key = create_signing_key(conf.request_authentication.secret, current_date)
  local signature_raw = openssl_hmac.new(signing_key, "sha256"):final(string_to_sign)
  local signature_hex = str.to_hex(signature_raw)

  if conf.request_authentication.log then
    local log_message = "The signature has been created " .. signature_hex ..
        " with date " .. current_precise_date ..
        " for the request " .. canonical_request
    kong.log.notice(log_message)
  end

  local credential = conf.request_authentication.access_id .. "/" .. credential_scope
  local auth_header = GCLOUD_SIGNING_ALGORITHM .. " " ..
      "Credential=" .. credential ..
      ", SignedHeaders=" .. GCLOUD_SIGNED_HEADERS ..
      ", Signature=" .. signature_hex

  kong.service.request.set_header("authorization", auth_header)
  kong.service.request.set_header("x-goog-date", current_precise_date)
  kong.service.request.set_header("x-goog-content-sha256", GCLOUD_UNSIGNED_PAYLOAD)
end

local function transform_uri(conf)
  if not conf.path_transformation.enabled then
    return
  end

  local service_path = get_service_path()
  local req_path = kong.request.get_path()
  local normalized_path = get_normalized_path(conf)
  if conf.path_transformation.log then
    local log_message = "The upstream path may be modifed. The request path " .. req_path ..
        ", the service path " .. service_path ..
        ", the normalized path " .. normalized_path
    kong.log.notice(log_message)
  end

  kong.service.request.set_path(normalized_path)
  kong.service.request.set_raw_query("")
end

local function add_service_headers(conf)
  if not conf.service_headers.enabled then
    return
  end

  local real_ip = kong.request.get_header("x-real-ip")
  if not real_ip or real_ip == "" then
    real_ip = "0.0.0.0"
  end
  local request_id = kong.request.get_header("x-request-id")
  if not request_id or request_id == "" then
    request_id = uuid.generate_v4()
  end
  local geoip_country = kong.request.get_header("x-geoip-country")
  if not geoip_country or geoip_country == "" then
    geoip_country = 'US'
  end
  local geoip_region_code = kong.request.get_header("x-geoip-region-code")
  if not geoip_region_code or geoip_region_code == "" then
    geoip_region_code = 'CA'
  end

  kong.response.add_header("X-Real-Ip", real_ip)
  kong.response.add_header("X-Request-Id", request_id)
  kong.response.add_header("X-Geoip-Country", geoip_country)
  kong.response.add_header("X-Geoip-Region-Code", geoip_region_code)

  local country_code_cookie = string.format("sb_country_code=%s;Path=/;Max-Age=600", geoip_country)
  local region_code_cookie = string.format("sb_region_code=%s;Path=/;Max-Age=600", geoip_region_code)
  kong.response.add_header("Set-Cookie", country_code_cookie)
  kong.response.add_header("Set-Cookie", region_code_cookie)

  if conf.service_headers.log then
    local log_message = "The service headers has been added. The request-id " .. request_id ..
        ", the geoip country " .. geoip_country ..
        ", the geoip region code " .. geoip_region_code
    kong.log.notice(log_message)
  end
end

function _M.execute(conf)
  do_authentication(conf)
  transform_uri(conf)
  add_service_headers(conf)
end

return _M
