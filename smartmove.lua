local smartmove = {}
local robot = require("robot")
local c = require("component")
local ic = c.inventory_controller
local sides = require("sides")

-- Utility that keeps track of the robot's movements so it knows where it is relative to the starting location.
-- Coordinates have nothing to do with map coordinates, it does not rely on the map upgrade.
-- X axis: The direction the robot was initially facing
-- Z axis: Right side direction
-- Y axis: Up and down
-- Starting point is 0,0,0 (X,Z,Y)

SmartMove = {
}

function SmartMove:_climb(direction)
  local result
  if direction == 1 then
    result = robot.up()
  else
    result = robot.down()
  end

  if result then
    self.posY = self.posY + direction
  end

  return result
end

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
      self.posZ = self.posZ + (direction*self.orient/2)
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
function SmartMove:up()
  return self:_climb(1)
end
function SmartMove:down()
  return self:_climb(-1)
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

function SmartMove:moveToX(x)
  local moved = false
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

  return self.posX == x, moved
end

function SmartMove:moveToZ(z)
  local moved = false
  if self.posZ ~= z then
    if self.posZ < z then
      direction = 2
    else
      direction = -2
    end
    self:faceDirection(direction)
    while self.posZ ~= z and self:forward() do
      moved = true
    end
  end

  return self.posZ == z, moved
end

function SmartMove:moveToY(y)
  local moved = false
  if self.posY ~= y then
    if self.posY < y then
      direction = 1
    else
      direction = -1
    end
    while self.posY ~= y and self:_climb(direction) do
      moved = true
    end
  end

  return self.posY == y, moved
end

function SmartMove:moveToXZ(x, z)
  -- first try X
  local resultX, movedX = self:moveToX(x)
  -- then try Z
  local resultZ, movedZ = self:moveToZ(z)

  -- if X failed but we moved Z, we can try X again (might be unblocked now)
  if not resultX and movedZ then
    local innerResult, innerMoved = self:moveToXZ(x, z)
    return innerResult, (innerMoved or movedX or movedZ)
  end

  -- successful if we ended up where we wanted to be
  return (self.posZ == z and self.posX == x), (movedX or movedZ)
end

function SmartMove:moveToXZY(x, z, y)
  -- try horizontal movement first
  local resultXZ, movedXZ = self:moveToXZ(x, z)
  -- now climb
  local resultY, movedY = self:moveToY(y)

  -- if XZ failed but we moved Y, we can try XZ again (might be unblocked now)
  if not resultXZ and movedY then
    local innerResult, innerMoved = self:moveToXZY(x, z, y)
    return innerResult, (innerMoved or movedXZ or movedY)
  end

  -- successful if we ended up where we wanted to be
  return (self.posZ == z and self.posX == x and self.posY == y), (movedXZ or movedY)
end

function SmartMove:findInventory(strafeDirection, maxBlocks, dontCheckCurrentSpot, minimumInventorySize)
  minimumInventorySize = minimumInventorySize or 1

  if not dontCheckCurrentSpot then
    local invSize = ic.getInventorySize(sides.bottom);
    if invSize ~= nil and invSize >= minimumInventorySize then
      return invSize
    end
  end

  local wasOrient = self.orient
  local wasX = self.posX
  local wasY = self.posZ
  self:faceDirection(strafeDirection)

  local moved = 0
  while moved < maxBlocks do
    if not self:forward() then
      break
    end
    moved = moved + 1
    invSize = ic.getInventorySize(sides.bottom);
    if invSize ~= nil and invSize >= minimumInventorySize then
      break
    end
  end
  if invSize == nil or invSize < minimumInventorySize then
    self:moveTo(wasX, wasY)
  end

  self:faceDirection(wasOrient)
  return invSize
end

function smartmove.new(o)
  o = o or {}
  setmetatable(o, { __index = SmartMove })
  o.posX = 0
  o.posZ = 0
  o.posY = 0
  o.orient = 1
  return o
end

return smartmove