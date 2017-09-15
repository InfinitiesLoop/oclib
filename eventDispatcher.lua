local event = require("event")

local eventDispatcher = {}
local EventDispatcher = {}

function eventDispatcher.new(o, handlers)
  o = o or {}
  setmetatable(o, { __index = EventDispatcher })
  o.handlers = handlers
  return o
end

function EventDispatcher:handleEvent(eventName, ...)
  if eventName == nil then
    return false
  end
  if self.handlers["on_"..eventName] then
    self.handlers["on_"..eventName](self.handlers, ...)
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