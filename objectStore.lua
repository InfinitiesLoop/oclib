local serializer = require("serializer")
local filesystem = require("component").filesystem
local ensuredDirExists = false

local function ensureDirExists()
  if not ensuredDirExists then
    filesystem.makeDirectory("/usr/objectstore")
    ensuredDirExists = true
  end
end

local function saveObject(name, obj)
  if filesystem == nil then
    return false
  end
  ensureDirExists()
  local str = serializer.serialize(obj)
  local file = io.open("/usr/objectstore/" .. name, "w")
  file:write(str)
  file:close()
  return true
end

local function loadObject(name)
  if filesystem == nil then
    return nil
  end
  ensureDirExists()
  local status, result = pcall(function() return io.lines("/usr/objectstore/" .. name) end)
  if not status then return false end

  local lines = {}
  for line in result do
    lines[#lines+1] = line
  end
  return serializer.deserializeLines(lines)
end

return {
  saveObject = saveObject,
  loadObject = loadObject
}