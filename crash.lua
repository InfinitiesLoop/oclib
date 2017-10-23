local shell = require("shell")
local fs = require("filesystem")

local args = {...}
local elog = shell.resolve(table.remove(args, 1))
local path = shell.resolve(table.remove(args, 1))

if not elog or not path then
  print("USAGE: crash <error log path> <path to program> [arguments...]")
  return 1
end

if not fs.exists(path) or fs.isDirectory(path) then
  print("Invalid path.")
  print("USAGE: crash <error log path> <path to program> [arguments...]")
  return 1
end

if not fs.exists(fs.path(elog)) then
  fs.makeDirectory(fs.path(elog))
end

local result = {xpcall(loadfile(path), debug.traceback, table.unpack(args))}

if result[1] then
  return table.unpack(result, 2)
else
  print("Program crashed.")
  local file = io.open(elog, "w")
  file:write(result[2])
  file:close()
  print("Error log saved to: " .. elog)
  return 0
end
