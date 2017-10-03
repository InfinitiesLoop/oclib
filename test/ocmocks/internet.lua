local internet = {}

function internet.request(url)
  -- we will simulate by using wget to get the content and lines to iterate chunks of it
  os.execute("wget " .. url .. " /tmp/oclib_request")
  local file = io.open("/tmp/oclib_request")
  local content = file:read("*a")
  return function()
    local c = content
    content = nil
    return c
  end
end

package.preload.internet = function() return internet end
