local eventDispatcher = require("eventDispatcher")
local shell = require("shell")
local objectStore = require("objectStore")
local component = require("component")
local model = require("builder/model")
local pathing = require("builder/pathing")
local smartmove = require("smartmove")
local inventory = require("inventory")
local util = require("util")
local modem = component.modem
local robot
local ic

local builder = {}
local Builder = {}

--local NEEDS_CHARGE_THRESHOLD = 0.1
local FULL_CHARGE_THRESHOLD = 0.95

function Builder:start()
  if not self.options.loadedModel then
    self:loadModel()
    self:saveState()
  end
  -- require stuff, open port
  robot = require("robot")
  ic = component.inventory_controller
  modem.open(self.options.port)

  -- see what our tool is
  ic.equip()
  local tool = ic.getStackInInternalSlot(1)
  if tool == nil or type(tool.maxDamage) ~= "number" then
    ic.equip()
    print("I dont seem to have a tool equipped! I won't be able to clear any existing blocks, I hope that's ok.")
  else
    self.toolName = tool.name
  end
  ic.equip()

  -- maybe enable chunk loading
  if self.options.chunkloader then
    local result, chunkloader = pcall(function() return component.chunkloader end)
    if result then
      chunkloader.setActive(false)
      if chunkloader.setActive(true) then
        print("chunkloader is active")
      end
    end
  end

  -- set up a smartmove object that is configured to indicate we are standing
  -- where the robot's starting point and orientation is.
  self.move = smartmove:new()
  local startPoint = self.options.loadedModel.levels[1].startPoint
  self.move.posX = -startPoint[1]
  self.move.posZ = startPoint[2]
  self.move.posY = 1
  -- the 3rd item of the startpoint vector is which way the robot is facing.
  -- we need to adjust smartmove's orientation to match since it defaults to `1` (+x)
  if startPoint[3] == 'v' then
    self.move.orient = -1
  elseif startPoint[3] == '^' then
    self.move.orient = 1
  elseif startPoint[3] == '<' then
    self.move.orient = -2
  elseif startPoint[3] == '>' then
    self.move.orient = 2
  end
  self.originalOrient = self.move.orient -- just so we know which way to face when shutting down
  -- there, now smartmove's state corresponds to our location within the level and the direction
  -- we are facing.

  local result
  local isDone
  result, isDone = self:iterate()
  while (result and not isDone and not self.returnRequested) do
    print("Headed out again!")
    result, isDone = self:iterate()
  end

  if isDone then
    print("Build complete.")
  elseif self.returnRequested then
    print("You called, master?")
  elseif not result then
    print("Halting.")
  end

  return isDone or false
end

function Builder:gotoNextBuildLevel()
  -- we build from top down so find the top most level that isn't complete
  local m = self.options.loadedModel
  local levelNum, level = model.topMostIncompleteLevel(m)
  if not level then
    return false
  end

  while self.move.posY < levelNum do
    if not self:gotoNextLevelUp() then
      return false
    end
  end
  return true
end

function Builder:gotoNextLevelUp()
  local thisLevel = self.options.loadedModel.levels[self.move.posY]
  local nextLevel = self.options.loadedModel.levels[self.move.posY + 1]
  local path = pathing.pathFromDropPoint(thisLevel, nextLevel.dropPoint)

  if not self:followPath(path) then
    return false
  end
  if not self:ensureClearUp() or not self.move:up() then
    return false
  end
  return true
end

function Builder:gotoNextLevelDown(isReturningToStart)
  -- we can assume we're standing on the droppoint of the level we want to exit.
  -- so just move downward, then 'build up' to complete the level above. then
  -- we should navigate to the droppoint of the new level from which building can
  -- begin.
  local thisLevel = self.options.loadedModel.levels[self.move.posY]
  local nextLevel = self.options.loadedModel.levels[self.move.posY - 1]
  local buildPoint = {-self.move.posX, self.move.posZ}
  if not self.move:down() then
    return false, "could not move downward"
  end
  if not isReturningToStart then
    -- when returning ot start we dont want to build blocks on the way
    if not self:buildBlockUp(thisLevel, buildPoint) then
      return false, "could not build final block on level " .. (self.move.posY+1) ..
        " point " .. model.pointStr(buildPoint)
    end
  end

  -- we're on the level, lets get to the droppoint for it
  local path = pathing.pathToDropPoint(nextLevel, thisLevel.dropPoint)
  if not self:followPath(path, isReturningToStart) then
    return false
  end
  return true
end

function Builder:ensureClearAdj(p)
  if not model.isClear(self.options.loadedModel.levels[self.move.posY], p) then
    -- make sure the block we're about to move into is cleared.
    self.move:faceXZ(-p[1], p[2])
    -- is the spot we're about to move into occupied by something we should clear out?
    local isBlocking, entityType = robot.detect()
    if isBlocking or entityType ~= "air" then
      local result = robot.swing()
      if not result then
        -- something is in the way and we couldnt deal with it
        return false, "could not clear whatever is in " .. model.pointStr(p)
      end
    end
    -- the space is clear or we just made it clear, mark it as so
    model.set(self.options.loadedModel.levels[self.move.posY].statuses, p, 'O')
    self:saveState()
  end
  return true
end

function Builder:ensureClearUp()
  local upperLevel = self.options.loadedModel.levels[self.move.posY + 1]
  if not upperLevel then
    error("Tried to clearUp but no level above us at posY=" .. self.move.posY)
  end

  local p = {-self.move.posX, self.move.posZ}
  if not model.isClear(upperLevel, p) then
    -- is the spot we're about to move into occupied by something we should clear out?
    local isBlocking, entityType = robot.detectUp()
    if isBlocking or entityType ~= "air" then
      local result = robot.swingUp()
      if not result then
        -- something is in the way and we couldnt deal with it
        return false, "could not clear whatever is above me at " .. model.pointStr(p)
      end
    end
    -- the space is clear or we just made it clear, mark it as so
    model.set(upperLevel.statuses, p, 'O')
    self:saveState()
  end
  return true
end

function Builder:buildBlock(level, buildPoint)
  if not self:ensureClearAdj(buildPoint) then
    return false, "could not ensure buildpoint was clear at " .. model.pointStr(buildPoint)
  end
  self.move:faceXZ(-buildPoint[1], buildPoint[2])

  local blockName = model.blockAt(self.options.loadedModel, level, buildPoint)
  if (blockName and blockName ~= "!air") then
    if not inventory.selectItem(blockName) then
      -- we seem to be out of this material
      return false
    end
  end
  local result, reason = robot.place()
  if not result then
    return false, "could not place block " .. blockName .. ": " .. reason
  end

  -- mark that we have indeed built this point
  model.set(level.statuses, buildPoint, 'D')
  self:saveState()

  return true
end

function Builder:buildBlockUp(level, buildPoint)
  local blockName = model.blockAt(self.options.loadedModel, level, buildPoint)
  if (blockName and blockName ~= "!air") then
    if not inventory.selectItem(blockName) then
      -- we seem to be out of this material
      return false
    end
  end
  local result, reason = robot.placeUp()
  if not result then
    return false, "could not place block " .. blockName .. ": " .. reason
  end

  -- mark that we have indeed built this point
  model.set(level.statuses, buildPoint, 'D')
  self:saveState()

  return true
end

function Builder:buildCurrentLevel()
  local l = self.options.loadedModel.levels[self.move.posY]
  local currentPoint = l.dropPoint
  repeat
    local result = pathing.findNearestBuildSite(l, currentPoint)
    if result then
      local buildPoint = result[1]
      local standPoint = result[2][#result[2]] or currentPoint

      -- go where we need to go
      if not self:followPath(result[2]) then
        return false, "couldn't follow path to build site"
      end

      -- build the block we need to build
      local buildResult, reason = self:buildBlock(l, buildPoint)
      if not buildResult then
        return false, reason
      end
      currentPoint = standPoint
    else
      return true
    end
  until not result
  return false, "unknown"
end

function Builder:followPath(path, isReturningToStart)
  --print("follow path: " .. model.pathStr(path))
  -- follow the given path, clearing blocks if necessary as we go,
  -- and saving the state of those blocks
  for _,p in ipairs(path) do
    --print(model.pointStr(p), self.move.orient)
    if not isReturningToStart then
      -- when returning to start we dont want to do ensureClear
      if not self:ensureClearAdj(p) then
        return false, "could not ensure adjacent spot was clear at " .. model.pointStr(p)
      end
    end
    -- move!
    if not self.move:moveToXZ(-p[1], p[2]) then
      return false, "could not move into " .. model.pointStr(p)
    end
  end
  return true
end

function Builder:backToStart() --luacheck: no unused args
  -- something went wrong the robot needs to get back home (charge level, etc)
  -- first thing we need to do is get to the droppoint for the level we are on.
  local thisLevel = self.options.loadedModel.levels[self.move.posY]
  --print("back to start from " .. model.pointStr({-self.move.posX, self.move.posZ}))
  local path = pathing.pathToDropPoint(thisLevel, {-self.move.posX, self.move.posZ})
  if not self:followPath(path, true) then
    return false, "backToStart could not get to droppoint of current level"
  end
  -- now we just need to follow drop points down the first level
  while self.move.posY > 1 do
    if not self:gotoNextLevelDown(true) then
      return false, "backToStart could not navigate down a level"
    end
  end

  -- just to look nice and make restarts easy to deal with.
  self.move:faceDirection(self.originalOrient)

  -- we should be back on the charger now.
  print("waiting for charge...")
  if not util.waitUntilCharge(FULL_CHARGE_THRESHOLD, 600) then
    print("waited a long time and I didn't get charged enough :(")
    return false
  end

  -- things we need to worry about:
  -- 1. ran out of a specific material
  -- 2. might want to restock on materials we didn't run out of
  -- 3. inventory got full from clearing blocks
  -- 4. tool broke from clearing blocks
  -- 5. when restocking we dont want one item type to starve other types if invenotyr isn't full enough

  -- todo: inventory stuff, tools, etc

  return true
end

function Builder:iterate()
  if not self:gotoNextBuildLevel() then
    print("Could not get to the next level to build.")
    return self:backToStart()
  end

  -- now that we're on the right level (at its droppoint) we can start
  -- building it.
  -- todo: will need to be in a loop that goes down levels as it builds
  local firstLevel = true
  repeat
    if not firstLevel then
      if not self:gotoNextLevelDown() then
        return self:backToStart()
      end
    end
    firstLevel = false

    if not self:buildCurrentLevel() then
      return self:backToStart()
    end
  until self.move.posY == 1 -- todo actually check on the robot start point instead of assuming lvl 1
--print("done? " .. model.pointStr({self.move.posX, self.move.posZ}), self.move.orient)
  local returnedToStart = self:backToStart()
  return returnedToStart, true
end

function Builder:applyDefaults() --luacheck: no unused args
  self.options.port = tonumber(self.options.port or "888")
end

function Builder:saveState()
  return objectStore.saveObject("builder", self.options)
end

function Builder:loadState()
  local result = objectStore.loadObject("builder")
  if result ~= nil then
    self.options = result
    self:applyDefaults()
    return true
  end
  return false
end

function Builder:loadModel()
  self.options.loadedModel = model.load(self.options.model)
end

function builder.new(o)
  o = o or {}
  setmetatable(o, { __index = Builder })
  o:applyDefaults()
  o.eventDispatcher = eventDispatcher.new({}, o)
  return o
end

local args, options = shell.parse( ... )
if args[1] == 'help' then
  print("commands: start, resume, summon")
elseif args[1] == 'start' then
  if (args[2] == 'help') then
    print("usage: builder start --model=mymodel.model")
  else
    local b = builder.new({options = options})
    b:applyDefaults()
    b:start()
  end
elseif args[1] == 'resume' then
  local b = builder.new()
  if b:loadState() then
    b:start()
  else
    print("Cannot resume. Make sure the robot has a writable hard drive to save state in.")
  end
elseif args[1] == 'summon' then
  modem.broadcast(tonumber(options.port or "888"), "return")
end

return builder
