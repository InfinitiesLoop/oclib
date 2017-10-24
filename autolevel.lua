local shell = require("shell")
local robot = require("robot")
local ic = require("component").inventory_controller
local inventory = require("inventory")
local autolevel = {}
local AutoLevel = {}

function AutoLevel:start()
  robot.select(1)
  ic.equip()
  local tool = ic.getStackInInternalSlot(1)
  if tool == nil or type(tool.maxDamage) ~= "number" then
    ic.equip()
    print("I dont seem to have a tool equipped!")
    return false
  end
  ic.equip()
  self.toolName = tool.name

  robot.place()
  while true do
    if not robot.swing() then
      -- equip a fresh tool...
      if not inventory.equipFreshTool(self.toolName) then
        print("lost durability on tool and can't find a fresh one in my inventory!")
        return false
      end
      if not robot.place() then
        print("failed to place")
        return
      end
    else
      if not robot.place() then
        print("failed to place")
        return
      end
    end
  end
end

function AutoLevel:applyDefaults() --luacheck: no unused args
end

function autolevel.new(o)
  o = o or {}
  setmetatable(o, { __index = AutoLevel })
  o:applyDefaults()
  return o
end

local args, options = shell.parse( ... )
if args[1] == 'help' then
  print("commands: start")
elseif args[1] == 'start' then
  if (args[2] == 'help') then
    print("usage: autolevel start")
  else
    local a = autolevel.new({options = options})
    a:applyDefaults()
    a:start()
  end
end

return autolevel
