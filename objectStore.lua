local serializer = require("serializer")

local function saveObject(name, obj)
  local str = serializer.serialize(obj)
  os.execute("mkdir /usr/objectstore/")
  local file = io.open("/usr/objectstore/" .. name, "w")
  file:write(str)
  file:close()
  return true
end

local function loadObject(name)
  local status, result = pcall(io.lines("/usr/objectstore/" .. name))
  if not status then return false end
  return serializer.deserializeLines(result)
end

return {
  saveObject = saveObject,
  loadObject = loadObject
}