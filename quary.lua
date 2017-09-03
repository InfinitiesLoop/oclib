local util = require("util")
local smartmove = require("smartmove")
local inv = require("inventory")
local robot = require("robot")
local inventory = require("inventory")
local sides = require("sides")
local shell = require("shell")
local objectStore = require("objectStore")

local quary = {}

local NEEDS_CHARGE_THRESHOLD = 0.1
local FULL_CHARGE_THRESHOLD = 0.95

local Quary = {
}

function Quary:canMine() --luacheck: no unused args
  if inventory.toolIsBroken() then
    if not inventory.equipFreshTool() then
      print("lost durability on tool and can't find a fresh one in my inventory!")
      return false
    end
  end
  if inventory.isLocalFull() then
    print("inventory is full!")
    return false
  end
  -- todo: use generator if present
  if util.needsCharging(NEEDS_CHARGE_THRESHOLD) then
    print("charge level is low!")
    return false
  end
  return true
end

function Quary:_mineAhead()
  if not self:canMine() then
    return false
  end
  robot.swing()
  if not self.move:forward() then
    print("I hit something!")
    return false
  end
  if not self:canMine() then
    return false
  end
  robot.swingUp()
  if not self:canMine() then
    return false
  end
  robot.swingDown()
  if self.options.torches then
    if inv.isIdealTorchSpot(self.move.posZ, self.move.posX - 1) then
      if not inv.placeTorch() then
        -- not placing a torch isn't considered an error we need to worry about.
        -- basically, we tried.
        print("could not place a torch when needed.")
      end
    end
  end
  return true
end

function Quary:_mineAroundCorner()
  local orient = self.move.orient
  if orient == 1 then
    self.move:turnLeft()
  else
    self.move:turnRight()
  end
  if not self:_mineAhead() then
    return false
  end
  if orient == 1 then
    self.move:turnLeft()
  else
    self.move:turnRight()
  end
  return true
end

function Quary:_findStartingPoint()
  -- at the start of a quary, it might be a quary in progress.
  -- navigate the lanes to the left until we find where we left off.
  self.move:turnLeft()
  local moved = false
  while self.move:forward() do
    moved = true
    self.stepsWidth = self.stepsWidth + 1
    if self.stepsWidth >= self.options.width then
      print("looks like this quary is done, I couldn't find the starting point!")
      self.move:turnRight()
      return false
    end
  end

  -- found it, and it's the very beginning
  if not moved then
    print("looks like a new quary! may the diamonds be plentiful!")
  end

  -- there was a block up or down so we're already in the starting spot
  print("found starting point.")
  self.move:turnRight()
  return true
end

function Quary:mineNextLane()
  local steps = 0
  while (steps < (self.options.depth - 1)) do
    if not self:_mineAhead() then
      print("could not mine main part of lane")
      return false
    end
    steps = steps + 1
  end

  if not self:_mineAroundCorner() then
    print("could not turn corner")
    return false
  end

  steps = 0
  while (steps < (self.options.depth - 1)) do
    if not self:_mineAhead() then
      print("could not mine return part of lane")
      return false
    end
    steps = steps + 1
  end

  return true
end

function Quary:backToStart()
  if self.move:moveToXZY(0, 0, 0) then
    local result = self:dumpInventory()
    if not result then
      print("could not dump inventory.")
      self.move:moveToXZY(0, 0, 0)
      return false
    end
    if not self.move:moveToXZY(0, 0, 0) then
      print("could not return to 0,0,0 after dumping inventory.")
      return false
    end
  else
    print("could not get back to 0,0,0 for some reason.")
    return false
  end

  self.move:faceDirection(1)

  -- charge if needed
  if util.needsCharging(NEEDS_CHARGE_THRESHOLD) then
    if not util.waitUntilCharge(FULL_CHARGE_THRESHOLD, 300) then
      print("waited a long time and I didn't get charged enough :(")
      return false
    end
  end

  -- get a new tool if needed
  if inventory.toolIsBroken() then
    if not inventory.equipFreshTool() then
      print("could not find a fresh tool to equip!")
      return false
    end
  end

  -- todo: need to check for torch supply too

  -- should be no reason why we cant get back out there now!
  return true
end

function Quary:dumpInventory()
  while true do
    local result = self.move:findInventory(-2, 5, true, 16)
    if result == nil or result <= 0 then
      return false
    end
    result = inventory.dropAll(sides.bottom, 5)
    if result then
      return true
    end
  end
end

function Quary:iterate()
  self.stepsWidth = 0
  if not self:_mineAhead() then
    print("could not enter quary area.")
    self:backToStart()
    return false
  end

  if not self:_findStartingPoint() then
    print("could not find starting point.")
    self:backToStart()
    return false
  end

  while self.stepsWidth < self.options.width do
    local result = self:mineNextLane()
    if not result then
      print("failed to mine lane")
      return self:backToStart()
    end

    -- move to next lane
    if not self:_mineAroundCorner() then
      print("failed to turn corner into new lane.")
      return self:backToStart()
    end

    self.stepsWidth = self.stepsWidth + 2
  end
  local returnedToStart = self:backToStart()

  return returnedToStart, (self.stepsWidth >= self.options.width)
end

function Quary:start()
  local result
  local isDone
  result, isDone = self:iterate()
  while (result and not isDone) do
    print("headed out again!")
    result, isDone = self:iterate()
  end

  return isDone or false
end

function Quary:saveState()
  return objectStore.saveObject("quary", self.options)
end

function Quary:loadState()
  local result = objectStore.loadObject("quary")
  if result ~= nil then
    self.options = result
    return true
  end
  return false
end

function quary.new(o)
  o = o or {}
  setmetatable(o, { __index = Quary })
  o.move = o.move or smartmove.new()
  o.options = o.options or {}
  o.options.width = tonumber(o.options.width or "10")
  o.options.depth = tonumber(o.options.depth or "10")
  o.options.height = tonumber(o.options.height or "3")
  o.options.torches = o.options.torches == true or o.options.torches == "true" or o.options.torches == nil
  return o
end

local args, options = shell.parse( ... )
if args[1] == 'start' then
  if (args[2] == 'help') then
    print("usage: quary start --width=100 --depth=100 --height=9 --torches=true")
  else
    local q = quary.new({options = options})
    q:saveState()
    q:start()
  end
elseif args[1] == 'resume' then
  local q = quary.new()
  if q:loadState() then
    q:start()
  else
    print("cannot resume")
  end
end

return quary
