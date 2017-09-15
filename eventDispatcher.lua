local event = require("event")

local eventDispatcher = {}
local EventDispatcher = {}

function eventDispatcher.new(o)
  o = o or {}
  setmetatable(o, { __index = EventDispatcher })
  return o
end

function EventDispatcher:handleEvent(eventName, ...)
  if eventName == nil then
    return false
  end
  if self["on_"..eventName] then
    self["on_"..eventName](...)
  end
  return true
end

function EventDispatcher:doEvents()
  while true do
    if not self:handleEvent(event.pull(0)) then
      return
    end
  end
end

return eventDispatcher