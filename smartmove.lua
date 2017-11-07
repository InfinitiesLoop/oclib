local smartmove = {}
local c = require("component")
local ic
local sides = require("sides")
local event = require("event")

-- Utility that keeps track of the robot's movements so it knows where it is relative to the starting location.
-- Coordinates have nothing to do with map coordinates, it does not rely on the map upgrade.
-- X axis: The direction the robot was initially facing
-- Z axis: Right side direction
-- Y axis: Up and down
-- Starting point is 0,0,0 (X,Z,Y)

local SmartMove = {
}

function SmartMove:_tryClimb(direction)
  local timeout = self.moveTimeout
  local result
  repeat
    if direction == 1 then
      result = self.robot.up()
    else
      result = self.robot.down()
    end
    if not result and timeout > 0 then
      event.pull(1, "_smartmove")
    end
    timeout = timeout - 1
  until result or timeout <= 0
  return result
end

function SmartMove:_climb(direction, distance, atomic)
  distance = distance or 1
  local moveCount = 0

  while moveCount < distance do
    local result = self:_tryClimb(direction)

    if result then
      moveCount = moveCount + 1
      self.posY = self.posY + direction
    elseif atomic then
      -- failed to move, gotta undo
      local undid = self:_climb(-direction, moveCount, false)
      return false, undid
    else
      return false
    end
  end

  return true
end

function SmartMove:_tryMove(direction)
  local timeout = self.moveTimeout
  local result, reason
  repeat
    if direction == 1 then
      result, reason = self.robot.forward()
    else
      result, reason = self.robot.back()
    end
    if not result then
      print("smartmove: move fail: " .. reason)
    end
    if not result and timeout > 0 then
      if direction == -1 then
        direction = 1
        self.robot.turnAround()
      end
      self.robot.swing()
      event.pull(1, "_smartmove")
    end
    timeout = timeout - 1
  until result or timeout <= 0
  return result
end

function SmartMove:_move(direction)
  local result = self:_tryMove(direction)

  if result then
    if self.orient == 1 or self.orient == -1 then
      self.posX = self.posX + (direction*self.orient)
    else
      self.posZ = self.posZ + (direction*self.orient/2)
    end
  end
  return result
end

function SmartMove:summary()
  return '(' .. self.posX .. ',' .. self.posZ .. ',' .. self.posY .. ') orient ' .. self.orient
end

function SmartMove:forward()
  return self:_move(1)
end
function SmartMove:backward()
  return self:_move(-1)
end
function SmartMove:up(distance, atomic)
  return self:_climb(1, distance, atomic)
end
function SmartMove:down(distance, atomic)
  return self:_climb(-1, distance, atomic)
end
function SmartMove:advance(direction)
  -- see if we can go that way by just moving backward, to avoid having to turnaround
  if self.orient == -direction then
    return self:backward()
  else
    return self:faceDirection(direction) and self:forward()
  end
end
function SmartMove:faceXZ(x, z)
  if x ~= self.posX then
    if x < self.posX then
      self:faceDirection(-1)
    elseif x > self.posX then
      self:faceDirection(1)
    end
  elseif z ~= self.posZ then
    if z < self.posZ then
      self:faceDirection(-2)
    elseif z > self.posZ then
      self:faceDirection(2)
    end
  end
end

function SmartMove:swing(direction)
  return self:faceDirection(direction) and self.robot.swing()
end

function SmartMove:_turn(direction)
  local result
  if direction == 1 then
    result = self.robot.turnRight()
  else
    result = self.robot.turnLeft()
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
function SmartMove:turnAround()
  local result = self.robot.turnAround()
  if result then
    self.orient = -self.orient
  end
  return result
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
    self:turnAround()
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

function SmartMove:facing()
  local pos = { x = self.posX, z = self.posZ, y = self.posY }
  if self.orient == -2 then
    pos.z = pos.z - 1
  elseif self.orient == 2 then
    pos.z = pos.z + 1
  elseif self.orient == 1 then
    pos.x = pos.x + 1
  elseif self.orient == -1 then
    pos.x = pos.x - 1
  end
  return pos
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
    while self.posX ~= x and self:advance(direction) do
      moved = true
    end
  end

  return self.posX == x, moved
end

function SmartMove:moveToZ(z)
  local moved = false
  local direction
  if self.posZ ~= z then
    if self.posZ < z then
      direction = 2
    else
      direction = -2
    end
    while self.posZ ~= z and self:advance(direction) do
      moved = true
    end
  end

  return self.posZ == z, moved
end

function SmartMove:moveToY(y)
  local moved = false
  local direction
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
  local _, movedZ = self:moveToZ(z)

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
  local _, movedY = self:moveToY(y)

  -- if XZ failed but we moved Y, we can try XZ again (might be unblocked now)
  if not resultXZ and movedY then
    local innerResult, innerMoved = self:moveToXZY(x, z, y)
    return innerResult, (innerMoved or movedXZ or movedY)
  end

  -- successful if we ended up where we wanted to be
  return (self.posZ == z and self.posX == x and self.posY == y), (movedXZ or movedY)
end

function SmartMove:distanceFromStart()
  return math.abs(self.posX) + math.abs(self.posY) + math.abs(self.posZ)
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
  local wasZ = self.posZ
  self:faceDirection(strafeDirection)

  local moved = 0
  local invSize
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
    invSize = nil
    self:moveToXZ(wasX, wasZ)
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
  o.moveTimeout = o.moveTimeout or 0

  -- things we actually need

  o.robot = o.robot or require("robot")
  ic = c.inventory_controller

  return o
end

return smartmove