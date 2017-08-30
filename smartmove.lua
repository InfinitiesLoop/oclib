local smartmove = {}
local robot = require("robot")
local c = require("component")
local ic = c.inventory_controller
local sides = require("sides")

SmartMove = {
}

function SmartMove:_move(direction)
  local result
  if direction == 1 then
    result = robot.forward()
  else
    result = robot.back()
  end

  if result then
    if self.orient == 1 or self.orient == -1 then
      self.posX = self.posX + (direction*self.orient)
    else
      self.posY = self.posY + (direction*self.orient/2)
    end
  end
  return result
end

function SmartMove:forward()
  return self:_move(1)
end
function SmartMove:backward()
  return self:_move(-1)
end

function SmartMove:_turn(direction)
  local result
  if direction == 1 then
    result = robot.turnRight()
  else
    result = robot.turnLeft()
  end
  if result then
    if self.orient == 1 then
      self.orient = direction * 2
    elseif self.orient == -1 then
      self.orient = direction * -2
    elseif self.orient == 2 then
      self.orient = direction * -1
    elseif self.orient == -2 then
      self.orient = direction * 1
    end
  end
  return result
end

function SmartMove:turnRight()
  return self:_turn(1)
end
function SmartMove:turnLeft()
  return self:_turn(-1)
end

function SmartMove:forwardUntilBlocked()
  while self:forward() do
  end
end

function SmartMove:faceDirection(o)
  -- makes the robot oriented in the desired direction
  -- by turning in the appropriate direction
  if self.orient == o then
    return true
  end

  if self.orient == -o then
    -- 180
    self:turnRight()
    self:turnRight()
  -- probably could be more clever
  elseif o == -1 and self.orient == -2 then
    self:turnLeft()
  elseif o == -1 and self.orient == 2 then
    self:turnRight()
  elseif o == 1 and self.orient == -2 then
    self:turnRight()
  elseif o == 1 and self.orient == 2 then
    self:turnLeft()
  elseif o == -2 and self.orient == -1 then
    self:turnRight()
  elseif o == -2 and self.orient == 1 then
    self:turnLeft()
  elseif o == 2 and self.orient == -1 then
    self:turnLeft()
  elseif o == 2 and self.orient == 1 then
    self:turnRight()
  end

  return true
end

function SmartMove:moveTo(x, y)
  local moved = false
  -- lets do X first, gotta reorient if necessary
  if self.posX ~= x then
    local direction
    if self.posX < x then
      direction = 1
    else
      direction = -1
    end
    self:faceDirection(direction)
    while self.posX ~= x and self:forward() do
      moved = true
    end
  end

  if self.posY ~= y then
    if self.posY < y then
      direction = 2
    else
      direction = -2
    end
    self:faceDirection(direction)
    while self.posY ~= y and self:forward() do
      moved = true
    end
  end

  -- try again
  if moved and (self.posY ~= y or self.posX ~= x) then
    self:moveTo(x, y)
  end

  return self.posY == y and self.posX == x
end

function SmartMove:findInventory(strafeDirection, maxBlocks, dontCheckCurrentSpot)
  if not dontCheckCurrentSpot then
    local invSize = ic.getInventorySize(sides.bottom);
    if invSize > 0 then
      return invSize
    end
  end

  local wasOrient = self.orient
  local wasX = self.posX
  local wasY = self.posY
  self:faceDirection(strafeDirection)

  local moved = 0
  while moved < maxBlocks do
    if not self:forward() then
      break
    end
    moved = moved + 1
    invSize = ic.getInventorySize(sides.bottom);
    if invSize > 0 then
      break
    end
  end
  if invSize == nil or invSize == 0 then
    self:moveTo(wasX, wasY)
  end

  self:faceDirection(wasOrient)
  return invSize
end

function smartmove.new(o)
  o = o or {}
  setmetatable(o, { __index = SmartMove })
  o.posX = 0
  o.posY = 0
  o.orient = 1
  return o
end

return smartmove