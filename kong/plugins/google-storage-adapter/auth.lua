local openssl_hmac = require "resty.openssl.hmac"
local sha256 = require "resty.sha256"
local str = require "resty.string"

local path = require "kong.plugins.google-storage-adapter.path"

local kong = kong

local GCLOUD_STORAGE_HOST = "storage.googleapis.com"
local GCLOUD_METHOD = 'GET'
local GCLOUD_SIGNING_ALGORITHM = 'GOOG4-HMAC-SHA256'
local GCLOUD_REGION = "auto"
local GCLOUD_SERVICE = 'storage'
local GCLOUD_REQUEST_TYPE = 'goog4_request'
local GCLOUD_SIGNED_HEADERS = 'host;x-goog-content-sha256;x-goog-date'
local GCLOUD_UNSIGNED_PAYLOAD = 'UNSIGNED-PAYLOAD'

local function create_canonical_request(conf, current_precise_date)
  local path = path.get_normalized_path(conf)

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

return {
  do_authentication = do_authentication
}