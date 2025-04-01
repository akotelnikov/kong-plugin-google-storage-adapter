local kong = kong

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
-- /linked-site/ru-RU/first-game-subpath/index.html -> /first-game/ru-RU/index.html
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

  if not conf.path_transformation.enabled then
    return req_path
  end

  -- by default we have the /sites prefix
  local prefix = conf.path_transformation.prefix
  if prefix then
    req_path = string.gsub(req_path, prefix, "")
  end

  -- site linking routes handling
  local main_domain = req_path:match("^/[a-zA-Z0-9%-%_]+/?") or ""
  local locale = req_path:match("%l%l%-%u%u/?") or ""
  local file_name = req_path:match("[a-zA-Z0-9-_]*%.?[a-zA-Z0-9-_]+%.[a-zA-Z0-9-_]+$") or ""
  local is_linked_site = service_path ~= main_domain

  if conf.path_transformation.log then
    local log_message = string.format(
      "The request path has been parsed successfully; The main domain is %s, the locale is %s, the file name is %s, the req path is %s",
      main_domain, locale, file_name, req_path)
    kong.log.notice(log_message)
  end
  if is_linked_site then
    local full_path = service_path .. locale .. file_name
    return add_index_file_to_path(full_path)
  else
    return add_index_file_to_path(req_path)
  end
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

return {
  transform_uri = transform_uri,
  get_normalized_path = get_normalized_path,
}