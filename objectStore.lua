local serializer = require("serializer")
local filesystem = require("component").filesystem
local ensuredDirExists = false

local objectstore = {
  baseDir = "/usr/objectstore"
}

local function ensureDirExists()
  if not ensuredDirExists then
    filesystem.makeDirectory(objectstore.baseDir)
    ensuredDirExists = true
  end
end

function objectstore.saveObject(name, obj)
  if filesystem == nil then
    return false
  end
  ensureDirExists()
  local str = serializer.serialize(obj)
  local file = io.open(objectstore.baseDir .. "/" .. name, "w")
  file:write(str)
  file:close()
  return true
end

function objectstore.loadObject(name)
  if filesystem == nil then
    return nil
  end
  ensureDirExists()
  local status, result = pcall(function() return io.lines(objectstore.baseDir .. "/" .. name) end)
  if not status then return false end

  local lines = {}
  for line in result do
    lines[#lines+1] = line
  end
  return serializer.deserializeLines(lines)
end

return objectstore
