local internet = {}

function internet.request(url)
  -- we will simulate by using wget to get the content and lines to iterate chunks of it
  os.execute("wget -nv -O  /tmp/oclib_request " .. url)
  local file = io.open("/tmp/oclib_request", "r")
  local content = file:read("*a")
  return function()
    local c = content
    content = nil
    return c
  end
end

package.preload.internet = function() return internet end
