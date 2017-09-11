local util = require("util")
local smartmove = require("smartmove")
local robot = require("robot")
local shell = require("shell")
local objectStore = require("objectStore")
local component = require("component")
local ic = component.inventory_controller
local inventory = require("inventory")
local chunkloader = component.chunkloader

local NEEDS_CHARGE_THRESHOLD = 0.1
local FULL_CHARGE_THRESHOLD = 0.95

local Cleanup = {
}

function Cleanup:ok() --luacheck: no unused args
  if util.needsCharging(NEEDS_CHARGE_THRESHOLD, self.move:distanceFromStart()) then
    print("charge level is low!")
    return false
  end
  return true
end

function Cleanup:selectCleanupMaterial()
  -- todo: move this into inventory stuff
  local stack = ic.getStackInInternalSlot()
  if not stack or stack.name ~= self.cleanMaterial then
    if not inventory.selectItem(self.cleanMaterial) then
      return false
    end
  end
  return true
end

function Cleanup:_cleanHere(isPickup)
  if not self:ok() then
    return false
  end
  if isPickup then
    robot.swingDown()
  else
    local _, blockType = robot.detectDown()
    if blockType == "liquid" then
      self:selectCleanupMaterial()
      local result = robot.placeDown()
      if not result then
        print("could not place a cleanup block")
        return false
      end
      self.placed = true
    elseif blockType == "solid" then
      -- this shouldnt happen but it might be left over from previous run
      -- dont really care if it fails
      robot.swingDown()
    end
  end
  return true
end

function Cleanup:backToStart()
  if not self.move:moveToXZY(0, 0, 0) then
    print("could not get back to 0,0,0 for some reason.")
    return false
  end

  self.move:faceDirection(1)

  -- charge if needed, accounting for the distance to the very end of the Cleanup since
  -- that might be how far it will need to travel
  if util.needsCharging(NEEDS_CHARGE_THRESHOLD,
    math.abs(self.options.width) + math.abs(self.options.height) + math.abs(self.options.depth)) then
    if not util.waitUntilCharge(FULL_CHARGE_THRESHOLD, 300) then
      print("waited a long time and I didn't get charged enough :(")
      return false
    end
  end

  return true
end

function Cleanup:iterate()
  self.stepsHeight = 1

  if not self.move:advance(1) then
    return false, "could not enter Cleanup area."
  end

  local firstLevel = true

  -- get to the starting level
  while self.stepsHeight < self.options.startHeight do
    if not self.move:down() then
      return false, "could not get to the starting level"
    end
    self.stepsHeight = self.stepsHeight + 1
  end

  local laneNum = 1
  -- get to the starting lane
  self.options.startLane = self.options.startLane or 1
  if laneNum < (self.options.startLane - 1) then
    local result = self.move:moveToXZ(1, -(self.options.startLane - 2))
    if not result then
      return false, "failed to return to the starting lane"
    end
    laneNum = self.options.startLane - 1
  end

  repeat
    -- no need to move down on the first level, robot starts on that level already
    if not firstLevel then
      -- return to the (1,0,_) point for the level we're currently on
      local result = self.move:moveToXZ(1, 0)
      if not result then
        return false, "failed to return to starting point to begin the next Cleanup level"
      end
      result = self.move:down()
      if not result then
        return false, "failed to move down to the next level"
      end
      self.options.startLane = 1
      self.stepsHeight = self.stepsHeight + 1
      self.options.startHeight = self.options.startHeight + 1
    end
    firstLevel = false

    self.placed = false
    self.lastLanePlaced = false

    local advanceToward = 1
    while laneNum <= self.options.width do
      self.options.startLane = laneNum
      if laneNum ~= 1 then
        -- turn corner
        if not self.move:advance(-2) then
          return false, "could not turn the corner"
        end
      end

      -- about to advance on a lane
      self.lastLanePlaced = self.placed
      self.placed = false

      -- go down lane
      for d=1,self.options.depth-1 do -- luacheck: no unused args
        if not self:_cleanHere() then
          return false, "could not clean here"
        end
        if not self.move:advance(advanceToward) then
          return false, "couldn't step forward"
        end
      end
      if not self:_cleanHere() then
        return false, "could not clean here"
      end

      -- pick up dirt from the previous lane
      if laneNum > 1 and self.lastLanePlaced then
        advanceToward = -advanceToward
        if not self.move:advance(2) then
          return false, "couldn't get back to the previous lane"
        end

        for d=1,self.options.depth-1 do -- luacheck: no unused args
          if not self:_cleanHere(true) then
            return false, "could not pick up dirt"
          end
          if not self.move:advance(advanceToward) then
            return false, "couldn't step forward"
          end
        end
        if not self:_cleanHere(true) then
          return false, "could not clean here"
        end

        -- now back to the lane we were in
        if not self.move:advance(-2) then
          return false, "couldn't get back start the next lane"
        end
      end

      laneNum = laneNum + 1
      advanceToward = -advanceToward
    end

    -- we need to pick up the last lane
    -- just turn around and go back down
    if self.placed then
      for d=1,self.options.depth-1 do -- luacheck: no unused args
        if not self:_cleanHere(true) then
          return false, "could not pick up dirt"
        end
        if not self.move:advance(advanceToward) then
          return false, "couldn't step forward"
        end
      end
      if not self:_cleanHere(true) then
        return false, "could not clean here"
      end
    end

  until self.stepsHeight >= self.options.height

  return true
end

function Cleanup:start()
  if self.options.chunkloader and chunkloader ~= nil then
    chunkloader.setActive(false)
    if chunkloader.setActive(true) then
      print("chunkloader is active")
    end
  end

  robot.select(1)
  local cleanMaterial = component.inventory_controller.getStackInInternalSlot(1)
  if not cleanMaterial then
    print("make sure you have dirt or something to use in slot 1.")
    return false
  end
  self.cleanMaterial = cleanMaterial.name

  repeat
    print("headed out!")
    local result, err = self:iterate()
    if not result then
      print(err)
      if not self:backToStart() then
        print("could not return to start, halting")
        return false
      end
    else
      print("cleanup complete, returning")
      self:backToStart()
      return true
    end
  until false
end

function Cleanup:saveState()
  return objectStore.saveObject("cleanup", self.options)
end

function Cleanup:loadState()
  local result = objectStore.loadObject("cleanup")
  if result ~= nil then
    self.options = result
    return true
  end
  return false
end

function Cleanup.new(o)
  o = o or {}
  setmetatable(o, { __index = Cleanup })
  o.move = o.move or smartmove.new()
  o.options = o.options or {}
  o.options.width = tonumber(o.options.width or "10")
  o.options.depth = tonumber(o.options.depth or "10")
  o.options.height = tonumber(o.options.height or "1")
  o.options.startHeight = tonumber(o.options.startHeight or "1")
  o.options.startLane = tonumber(o.options.startLane or "1")
  o.options.chunkloader = o.options.chunkloader == true or o.options.chunkloader == "true" or
    o.options.chunkloader == nil
  return o
end

local args, options = shell.parse( ... )
if args[1] == 'start' then
  if (args[2] == 'help') then
    print("usage: cleanup start --width=25 --depth=25 --height=9 --startHeight=6 --startLane=10")
  else
    local q = Cleanup.new({options = options})
    q:saveState()
    q:start()
  end
elseif args[1] == 'resume' then
  local q = Cleanup.new()
  if q:loadState() then
    q:start()
  else
    print("Cannot resume. Make sure the robot has a writable hard drive to save state in.")
  end
end

return Cleanup
