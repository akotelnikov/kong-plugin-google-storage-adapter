---
-- This file is shared with kong-plugin-sb-ab-testing
-- Would be better to create a mutual dependency package
--

local kong = kong

local function get_service_path()
  -- a service is being looked up by a route we created earlier
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
local function get_path(path_transformation_conf, target_path)
  if not target_path then
    target_path = get_service_path()
  end
  -- if there's any override to a particular page (e.g. 403.html)
  if string.match(target_path, "(.*).html$") then
    return target_path
  end

  local req_path = kong.request.get_path()

  -- by default we have the /sites prefix
  local prefix = path_transformation_conf.prefix
  if prefix then
    req_path = string.gsub(req_path, prefix, "")
  end

  if not path_transformation_conf.enabled then
    return req_path
  end

  -- multipage routes handling
  local main_domain = req_path:match("^/[a-zA-Z0-9%-%_]+/?") or ""
  local locale = req_path:match("%l%l%-%u%u/?") or ""
  local file_name = req_path:match("[a-zA-Z0-9-_]*%.?[a-zA-Z0-9-_]+%.[a-zA-Z0-9-_]+$") or ""
  local one_page_path = main_domain .. locale .. file_name
  local is_one_page_site = one_page_path == req_path

  if is_one_page_site then
    return add_index_file_to_path(req_path)
  else
    local full_path = target_path .. locale .. file_name
    if path_transformation_conf.log then
      local log_message = string.format(
        "Built path for the multipage site, the main domain %s, the locale path %s, the file name %s, the full path %s",
        main_domain, locale, file_name, full_path)
      kong.log.notice(log_message)
    end
    return add_index_file_to_path(full_path)
  end
end

return {
  get_service_path = get_service_path,
  add_index_file_to_path = add_index_file_to_path,
  get_path = get_path
}
