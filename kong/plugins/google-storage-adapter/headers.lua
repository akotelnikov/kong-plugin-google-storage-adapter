local uuid = require "resty.jit-uuid"

local kong = kong

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

return {
  add_service_headers = add_service_headers
}