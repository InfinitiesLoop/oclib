local util = require("util")
local smartmove = require("smartmove")
local inv = require("inventory")
local robot = require("robot")
local inventory = require("inventory")
local sides = require("sides")

local quary = {}

Quary = {
}

function Quary:canMine()
  local d, dcurrent, dmax = robot.durability()
  d = util.trunc(d or 0, 2)
  if d <= 0 then
    print("lost durability on tool!")
    return false
  end
  if inventory.isLocalFull() then
    print("inventory is full!")
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
  if inv.isIdealTorchSpot(self.move.posY, self.move.posX - 1) then
    if not inv.placeTorch() then
      print("could not place a torch when needed.")
      return false
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
    if self.stepsWidth >= self.width then
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
  while (steps < (self.depth - 1)) do
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
  while (steps < (self.depth - 1)) do
    if not self:_mineAhead() then
      print("could not mine return part of lane")
      return false
    end
    steps = steps + 1
  end

  return true
end

function Quary:backToStart()
  if self.move:moveTo(0, 0) then
    local result = self:dumpInventory()
    if not result then
      print("could not dump inventory.")
    end
    self.move:moveTo(0, 0)
  end

  self.move:faceDirection(1)
end

function Quary:dumpInventory()
  while true do
    local result = self.move:findInventory(-2, 5, true)
    if result == nil or result <= 0 then
      return false
    end
    local result = inventory.dropAll(sides.bottom, 5)
    if result then
      return true
    end
  end
end

function Quary:start()
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
  
  while self.stepsWidth < self.width do
    local result = self:mineNextLane()
    if not result then
      print("failed to mine lane")
      self:backToStart()
      return false
    end

    -- move to next lane
    if not self:_mineAroundCorner() then
      print("failed to turn corner into new lane.")
      self:backToStart()
      return false
    end

    self.stepsWidth = self.stepsWidth + 2
  end
  self:backToStart()
  return true
end

function quary.new(o)
  o = o or {}
  setmetatable(o, { __index = Quary })
  o.move = o.move or smartmove.new()
  return o
end

return quary
