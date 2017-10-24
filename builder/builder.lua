local eventDispatcher = require("eventDispatcher")
local shell = require("shell")
local objectStore = require("objectStore")
local component = require("component")
local model = require("builder/model")
local pathing = require("builder/pathing")
local smartmove = require("smartmove")
local inventory = require("inventory")
local util = require("util")
local sides = require("sides")
local modem = component.modem
local robot
local ic

local builder = {}
local Builder = {}

local NEEDS_CHARGE_THRESHOLD = 0.20
local FULL_CHARGE_THRESHOLD = 0.95

local function assert(cond, msg)
  if not cond then
    print(cond)
    error(msg)
  end
end

function Builder:statusCheck()
  self.eventDispatcher:doEvents()
  if self.returnRequested and not self.returning then
    self.returning = true
    return false, "Return was requested by my master"
  end
  if self.toolName and inventory.toolIsBroken() then -- todo: maybe should allow for more durability than normal.
    if not inventory.equipFreshTool(self.toolName) then
      if not self.isReturningToStart then
        -- we dont bail out if returning to start in this case, just hope we dont actually need the tool
        return false, "Lost durability on tool and can't find a fresh one in my inventory!"
      end
    end
  end
  if not self.isReturningToStart then
    if not self.cachedIsNotFull then
      local isFull = inventory.isLocalFull()
      if isFull then
        -- inventory is full but maybe we can dump some trash to make room
        if self.options.trashCobble then
          --todo: more specific so we dont drop mossy cobble, for example
          inventory.trash(sides.bottom, {"cobblestone","netherrack"})
          -- if it is STILL full then we're done here
          if inventory.isLocalFull() then
            return false, "Inventory is full!"
          end
        else
          return false, "Inventory is full!"
        end
      else
        self.cachedIsNotFull = true
      end
    end

    -- hacking
    if self._debugFailStatusCheck then
      return false, "forced failed status check"
    end

    -- need charging?
    if util.needsCharging(NEEDS_CHARGE_THRESHOLD) then
      return false, "Charge level is low!"
    end
  end
  return true
end

function Builder:on_modem_message(localAddr, remoteAddr, port, distance, command) --luacheck: no unused args
  print("received message from " .. remoteAddr .. ", distance of " .. distance .. ": " .. command)
  if command == "return" then
    self.returnRequested = true
    modem.send(remoteAddr, port, "returning")
  end
end

function Builder:start()
  if not self.options.loadedModel then
    print("Loading model...")
    self:loadModel()
    print("Saving state...")
    self:saveState()
  end

  if not self.options.resuming then
    -- a new build, make sure we don't think saved statuses are from a previous one.
    model.clearStatuses()
  end

  print("Checking things out...")

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
  self.move = smartmove:new({ moveTimeout = 60 })
  local startPoint = self.options.loadedModel.startPoint
  self.move.posX = -startPoint[1]
  self.move.posZ = startPoint[2]
  self.move.posY = startPoint[3]
  -- the 4th item of the startpoint vector is which way the robot is facing.
  -- we need to adjust smartmove's orientation to match since it defaults to `1` (+x)
  if startPoint[4] == 'v' then
    self.move.orient = -1
  elseif startPoint[4] == '^' then
    self.move.orient = 1
  elseif startPoint[4] == '<' then
    self.move.orient = -2
  elseif startPoint[4] == '>' then
    self.move.orient = 2
  end
  self.originalOrient = self.move.orient -- just so we know which way to face when shutting down
  -- there, now smartmove's state corresponds to our location within the level and the direction
  -- we are facing.

  repeat
    print("I'm off to build stuff, wish me luck!")
    local result, reason = self:iterate()
    if not result then
      print("Oh no! " .. (reason or "Unknown iterate failure."))
      self.isReturningToStart = true
      result, reason = self:backToStart()
      self.isReturningToStart = false
      if not result then
        print("I just can't go on :( " .. reason)
        print("Sorry I let you down, master. I'm at " .. model.pointStr({-self.move.posX,self.move.posY}))
        return false
      end
    else
      print("Job's done! Do you like it?")
      return true
    end
  until self.returnRequested

  if self.returnRequested then
    print("Yes, sir?")
  end

  return false
end

function Builder:completeLevelDown()
  -- we can assume we're standing on the droppoint of the level we want to exit.
  -- so just move downward, then 'build up' to complete the level above. then
  -- we should navigate to the droppoint of the new level from which building can
  -- begin.
  local thisLevel = self.options.loadedModel.levels[self.move.posY]
  local nextLevel = self.options.loadedModel.levels[self.move.posY - 1]
  print("Buttoning up level " .. thisLevel.num .. " and starting on level " .. nextLevel.num)
  local buildPoint = {-self.move.posX, self.move.posZ}
  if not self:ensureClearDown() or not self.move:down() then
    return false, "could not move downward"
  end

  if not self:buildBlockUp(thisLevel, buildPoint) then
    return false, "could not build final block on level " .. nextLevel.num ..
      " point " .. model.pointStr(buildPoint)
  else
    model.markLevelComplete(thisLevel)
    self:saveState()
    -- be sure statuses are cleared and saved that way, in case
    -- we crash between now and when the blocks of the next level load,
    -- else we could confuse the saved statuses for the next level.
    model.clearStatuses()
  end

  -- we're on the level, lets get to the droppoint for it
  local path = pathing.pathToDropPoint(nextLevel, model.dropPointOf(self.options.loadedModel, thisLevel))
  return self:followPath(path)
end

function Builder:completeLevelUp()
  -- we can assume we're standing on the droppoint of the level we want to exit.
  -- so just move upward, then 'build down' to complete the level below. then
  -- we should navigate to the droppoint of the new level from which building can
  -- begin.
  local thisLevel = self.options.loadedModel.levels[self.move.posY]
  local nextLevel = self.options.loadedModel.levels[self.move.posY + 1]
  print("Buttoning up level " .. thisLevel.num .. " and starting on level " .. nextLevel.num)
  local buildPoint = {-self.move.posX, self.move.posZ}
  if not self:ensureClearUp() or not self.move:up() then
    return false, "could not move upward"
  end

  if not self:buildBlockDown(thisLevel, buildPoint) then
    return false, "could not build final block on level " .. nextLevel.num ..
      " point " .. model.pointStr(buildPoint)
  else
    model.markLevelComplete(thisLevel)
    self:saveState()
    -- be sure statuses are cleared and saved that way, in case
    -- we crash between now and when the blocks of the next level load,
    -- else we could confuse the saved statuses for the next level.
    model.clearStatuses()
  end

  -- we're on the level, lets get to the droppoint for it
  local path = pathing.pathToDropPoint(nextLevel, model.dropPointOf(self.options.loadedModel, thisLevel))
  return self:followPath(path)
end

function Builder:gotoNextLevelUp(isReturningToStart)
  local thisLevel = self.options.loadedModel.levels[self.move.posY]
  local nextLevel = self.options.loadedModel.levels[self.move.posY + 1]

  if isReturningToStart then
    -- This means we are on a lower level, and we need to go up in order
    -- get back home. In that case, we should already be on the droppoint of
    -- the current level, so we go up, then get to that level's droppoint
    if not self:ensureClearUp() or not self.move:up() then
      return false
    end
    -- we will check if we actually already on the drop point and be sure not to load
    -- block data for this level if we are.
    local thisDropPoint = model.dropPointOf(self.options.loadedModel, thisLevel)
    local nextDropPoint = model.dropPointOf(self.options.loadedModel, nextLevel)
    if thisDropPoint[1] ~= nextDropPoint[1] or thisDropPoint[2] ~= nextDropPoint[2] then
      local path = pathing.pathToDropPoint(nextLevel, thisDropPoint, isReturningToStart)
      if not self:followPath(path) then
        return false
      end
    end
  else
    -- This means we are on an upper level, and we need to go up in order to
    -- navigate to the next upper-most level in order to continue building.
    -- In that case, we need to go from the droppoint of the current level to the
    -- droppoint of the upper level, then go up.
    local thisDropPoint = model.dropPointOf(self.options.loadedModel, thisLevel)
    local nextDropPoint = model.dropPointOf(self.options.loadedModel, nextLevel)
    -- in many cases we may already be standing on the droppoint, so avoid getting block
    -- and distance information
    if thisDropPoint[1] ~= nextDropPoint[1] or thisDropPoint[2] ~= nextDropPoint[2] then
      local path = pathing.pathFromDropPoint(thisLevel, nextDropPoint)
      if not self:followPath(path) then
        return false
      end
    end
    if not self:ensureClearUp() or not self.move:up() then
      return false
    end
  end

  return true
end

function Builder:gotoNextLevelDown(isReturningToStart)
  local thisLevel = self.options.loadedModel.levels[self.move.posY]
  local nextLevel = self.options.loadedModel.levels[self.move.posY - 1]

  if isReturningToStart then
    -- This means we are on an upper level, and we need to go down in order
    -- get back home. In that case, we should already be on the droppoint of
    -- the current level, so we go down, then get to that level's droppoint
    if not self:ensureClearDown() or not self.move:down() then
      return false
    end
    -- we will check if we actually already on the drop point and be sure not to load
    -- block data for this level if we are.
    local thisDropPoint = model.dropPointOf(self.options.loadedModel, thisLevel)
    local nextDropPoint = model.dropPointOf(self.options.loadedModel, nextLevel)
    if thisDropPoint[1] ~= nextDropPoint[1] or thisDropPoint[2] ~= nextDropPoint[2] then
      local path = pathing.pathToDropPoint(nextLevel, thisDropPoint, isReturningToStart)
      if not self:followPath(path) then
        return false
      end
    end
  else
    -- This means we are on lower level, and we need to go down in order to
    -- navigate to the next lower-most level in order to continue building.
    -- In that case, we need to go from the droppoint of the current level to the
    -- droppoint of the lower level, then go down.
    local thisDropPoint = model.dropPointOf(self.options.loadedModel, thisLevel)
    local nextDropPoint = model.dropPointOf(self.options.loadedModel, nextLevel)
    -- in many cases we may already be standing on the droppoint, so avoid getting block
    -- and distance information
    if thisDropPoint[1] ~= nextDropPoint[1] or thisDropPoint[2] ~= nextDropPoint[2] then
      local path = pathing.pathFromDropPoint(thisLevel, nextDropPoint)
      if not self:followPath(path) then
        return false
      end
    end
    if not self:ensureClearDown() or not self.move:down() then
      return false
    end
  end

  return true
end

function Builder:ensureClearAdj(p)
  -- required status check
  local status, reason = self:statusCheck()
  if not status then
    return false, reason
  end
  local level
  if not self.isReturningToStart then
    level = self.options.loadedModel.levels[self.move.posY]
    if model.isClear(level, p) then
      -- already clear
      return true
    end
  end
  -- make sure the block we're about to move into is cleared.
  self.move:faceXZ(-p[1], p[2])
  status, reason = self:smartSwing()
  if not status then
    return false, "could not swing at " .. reason .. " in " .. model.pointStr(p)
  end
  -- inventory could be full now
  self.cachedIsNotFull = false

  -- save the fact that it is clear so we dont need to do it again
  if not self.isReturningToStart then
    model.setStatus(level, p, 1)
  end
  return true
end

function Builder:smartSwing() -- luacheck: no unused args
  local isBlocking, entityType = robot.detect()
  while isBlocking or entityType ~= "air" do
    -- this is a LOOP because even after clearing the space there might still be something there,
    -- such as when gravel falls, or an entity has moved in the way.
    local result = robot.swing()
    if not result then
      -- perhaps the thing is a bee hive, which requires a scoop to clear.
      -- equip a scoop if we have one and try again.
      if inventory.equip("scoop") then
        result = robot.swing()
        -- switch back off the scoop
        ic.equip()
      end
      if not result then
        -- something is in the way and we couldnt deal with it
        return false, entityType
      end
    end
    isBlocking, entityType = robot.detect()
  end
  return true
end

function Builder:ensureClearUp()
  -- required status check
  local status, reason = self:statusCheck()
  if not status then
    return false, reason
  end

  local upperLevel = self.options.loadedModel.levels[self.move.posY + 1]
  if not upperLevel then
    error("Tried to clearUp but no level above us at posY=" .. self.move.posY)
  end
  local p = {-self.move.posX, self.move.posZ}
  -- is the spot we're about to move into occupied by something we should clear out?
  local isBlocking, entityType = robot.detectUp()
  if isBlocking or entityType ~= "air" then
    local result = robot.swingUp()
    if not result then
      -- something is in the way and we couldnt deal with it
      return false, "could not clear whatever is above me at " .. model.pointStr(p)
    end
    -- inventory could be full now
    self.cachedIsNotFull = false
  end
  return true
end

function Builder:ensureClearDown()
  -- required status check
  local status, reason = self:statusCheck()
  if not status then
    return false, reason
  end

  local lowerLevel = self.options.loadedModel.levels[self.move.posY - 1]
  if not lowerLevel then
    error("Tried to clearDown but no level below us at posY=" .. self.move.posY)
  end
  local p = {-self.move.posX, self.move.posZ}
  -- is the spot we're about to move into occupied by something we should clear out?
  local isBlocking, entityType = robot.detectDown()
  if isBlocking or entityType ~= "air" then
    local result = robot.swingDown()
    if not result then
      -- something is in the way and we couldnt deal with it
      return false, "could not clear whatever is below me at " .. model.pointStr(p)
    end
    -- inventory could be full now
    self.cachedIsNotFull = false
  end
  return true
end

function Builder:buildBlock(level, buildPoint)
  assert(buildPoint, "buildBlock: buildPoint is required")
  local result, reason = self:ensureClearAdj(buildPoint)
  if not result then
    return false, "could not ensure buildpoint was clear at " .. model.pointStr(buildPoint) .. ": " .. reason
  end

  local blockName = model.blockAt(self.options.loadedModel, level, buildPoint)
  if (blockName and blockName ~= "!air") then
    if not inventory.selectItem(blockName) then
      -- we seem to be out of this material
      return false, "no more " .. blockName
    end
    self.move:faceXZ(-buildPoint[1], buildPoint[2])
    result, reason = robot.place()
    if not result then
      return false, "could not place block " .. blockName .. ": " .. (reason or "unknown")
    end
    self.options.loadedModel.matCounts[blockName] = self.options.loadedModel.matCounts[blockName] - 1
  end

  -- mark that we have indeed built this point
  model.setStatus(level, buildPoint, 2)
  return true
end

function Builder:buildBlockUp(level, buildPoint)
  local blockName = model.blockAt(self.options.loadedModel, level, buildPoint)
  if (blockName and blockName ~= "!air") then
    if not inventory.selectItem(blockName) then
      -- we seem to be out of this material
      return false, "no more " .. blockName
    end
    local result, reason = robot.placeUp()
    if not result then
      return false, "could not place block " .. blockName .. ": " .. reason
    end
    self.options.loadedModel.matCounts[blockName] = self.options.loadedModel.matCounts[blockName] - 1
  end

  -- mark that we have indeed built this point
  model.setStatus(level, buildPoint, 2)
  return true
end

function Builder:buildBlockDown(level, buildPoint)
  local blockName = model.blockAt(self.options.loadedModel, level, buildPoint)
  if (blockName and blockName ~= "!air") then
    if not inventory.selectItem(blockName) then
      -- we seem to be out of this material
      return false, "no more " .. blockName
    end
    local result, reason = robot.placeDown()
    if not result then
      return false, "could not place block " .. blockName .. ": " .. reason
    end
    self.options.loadedModel.matCounts[blockName] = self.options.loadedModel.matCounts[blockName] - 1
  end

  -- mark that we have indeed built this point
  model.setStatus(level, buildPoint, 2)
  return true
end

function Builder:buildCurrentLevel()
  local l = self.options.loadedModel.levels[self.move.posY]
  print("Starting on level " .. l.num)
  local currentPoint = model.dropPointOf(self.options.loadedModel, l)
  repeat
    local result = pathing.findNearestBuildSite(self.options.loadedModel, l, currentPoint)
    if result then
      local buildPoint = result[1]
      local standPoint = result[2][#result[2]] or currentPoint

      -- go where we need to go
      local followResult, followReason = self:followPath(result[2])
      if not followResult then
        model.saveStatuses(l)
        return false, "Couldn't follow path to build site: " .. followReason
      end

      -- build the block we need to build
      local buildResult, reason = self:buildBlock(l, buildPoint)
      if not buildResult then
        model.saveStatuses(l)
        return false, reason
      end
      currentPoint = standPoint
    else
      -- due to air blocks and optimizations, when the level is complete we might
      -- not be standing on the dropoint. so just be sure we are...
      local returnPath = pathing.pathToDropPoint(l, currentPoint)
      local followResult, followReason = self:followPath(returnPath)
      model.saveStatuses(l)
      if not followResult then
        return false, "Couldn't follow path to droppoint after level completion: " .. followReason
      end
      return true
    end
  until not result
  return false, "unknown"
end

function Builder:followPath(path)
  --print("follow path: " .. model.pathStr(path))
  -- follow the given path, clearing blocks if necessary as we go,
  -- and saving the state of those blocks
  for _,p in ipairs(path) do
    local status, reason = self:ensureClearAdj(p)
    if not status then
      return false, "could not ensure adjacent spot was clear at " .. model.pointStr(p) .. ": " .. reason
    end

    -- move!
    if not self.move:moveToXZ(-p[1], p[2]) then
      self:debugLoc("followPath failed to move into " .. model.pointStr(p))
      return false, "could not move into " .. model.pointStr(p)
    end
  end
  return true
end

function Builder:dumpInventoryAndResupply()
  local maxAttempts = 10
  local missingMaterial = nil
  while maxAttempts > 0 do
    -- find a chest...
    maxAttempts = maxAttempts - 1
    local result = self.move:findInventory(-2, 5, true, 16)
    if result == nil or result <= 0 then
      -- no inventory found within 5 blocks so we're done here.
      -- but, its ok if our inventory is not full and we have at least 1
      -- block of each required material...
      local isLocalFull = inventory.isLocalFull()
      local hasMats = inventory.hasMaterials(self.options.loadedModel.matCounts)
      return not isLocalFull and hasMats
    end

    -- remove excess materials that we probably picked up while building...
    local desupplied = inventory.desupply(sides.bottom, self.options.loadedModel.matCounts, 512)
    -- pick up any materials we are missing, if any are present
    local _, hasZeroOfSomething = inventory.resupply(sides.bottom, self.options.loadedModel.matCounts, 512)

    if not desupplied then
      -- maybe now that we picked stuff up we can successfully desupply again
      desupplied = inventory.desupply(sides.bottom, self.options.loadedModel.matCounts, 512)
    end

    -- drop broken tools and pick up fresh ones, if we had a tool to begin with
    -- we aren't tracking if this succeeds or not, because combined with the de/resupply stuff
    -- its kinda complex. If we end up without a tool we may not even need one, so I dunno.
    if self.toolName then
      inventory.dropBrokenTools(sides.bottom, self.toolName)
    end
    if self.toolName then
      inventory.pickUpFreshTools(sides.bottom, self.toolName)
    end

    -- are we good?
    if desupplied and not hasZeroOfSomething then
      return true
    end
    missingMaterial = missingMaterial or hasZeroOfSomething

    -- hmm, go over to the next chest then.
  end

  if missingMaterial then
    print("I seem to be fresh out of " .. missingMaterial)
  end
  return false
end

function Builder:backToStart() --luacheck: no unused args
  -- something went wrong the robot needs to get back home (charge level, etc)
  -- first thing we need to do is get to the droppoint for the level we are on.
  local thisLevel = self.options.loadedModel.levels[self.move.posY]
  print("Headed home from level " .. thisLevel.num .. " at " .. model.pointStr({-self.move.posX, self.move.posZ}))
  local path = pathing.pathToDropPoint(thisLevel, {-self.move.posX, self.move.posZ})

  local result, reason = self:followPath(path)
  if not result then
    self:debugLoc("backToStart, FAILED to follow path!")
    return false, ("backToStart could not get to droppoint of current level: " .. reason)
  end

  -- now we just need to follow drop points down the starting level
  while self.move.posY > self.options.loadedModel.startPoint[3] do
    if not self:gotoNextLevelDown(true) then
      return false, "backToStart could not navigate down a level"
    end
  end
  while self.move.posY < self.options.loadedModel.startPoint[3] do
    if not self:gotoNextLevelUp(true) then
      return false, "backToStart could not navigate up a level"
    end
  end

  -- just to look nice and make restarts easy to deal with.
  self.move:faceDirection(self.originalOrient)

  -- we should be back on the charger now.
  print("Charging... ")
  if not util.waitUntilCharge(FULL_CHARGE_THRESHOLD, 600) then
    return false, "I'm out of energy sir!"
  end

  return true
end

function Builder:debugLoc(str)
  print("DEBUG: " .. str .. ": " .. model.pointStr({self.move.posX, self.move.posZ}) .. " y=" .. self.move.posY ..
    ", orient " .. self.move.orient)
end

function Builder:buildLowerLevels()
  local level = model.bottomMostIncompleteLevel(self.options.loadedModel)
  if not level then
    -- none left
    return true
  end
  -- try and get to that level
  while self.move.posY > level.num do
    print("Headed down a level to " .. level.num .. " from " .. self.move.posY ..
      " at " .. model.pointStr({-self.move.posX, self.move.posZ}))

    local result, reason = self:gotoNextLevelDown()
    if not result then
      return false, reason
    end
  end

  -- now that we are here we need to restore the statuses that were saved to disk
  model.loadStatuses(level)

  -- iterate through the levels
  local firstLevel = true
  repeat
    if not firstLevel then
      local result, reason = self:completeLevelUp()
      if not result then
        return false, reason
      end
    end
    firstLevel = false

    local result, reason = self:buildCurrentLevel()
    if not result then
      return false, reason
    end
    -- go until we are just about to get to the starting level
  until self.move.posY == self.options.loadedModel.startPoint[3] - 1

  -- button up the last lower level
  local result, reason = self:completeLevelUp()
  if not result then
    return false, reason
  end

  return true
end

function Builder:loadStatuses() -- luacheck: no unused args
  model.loadStatuses()
end

function Builder:buildUpperLevels()
  local level = model.topMostIncompleteLevel(self.options.loadedModel)
  if not level then
    -- none left
    return true
  end
  -- try and get to that level
  while self.move.posY < level.num do
    print("Headed up a level to " .. level.num .. " from " .. self.move.posY ..
      " at " .. model.pointStr({-self.move.posX, self.move.posZ}))

    local result, reason = self:gotoNextLevelUp()
    if not result then
      return false, reason
    end
  end

  -- now that we are here we need to restore the statuses that were saved to disk
  model.loadStatuses(level)

  -- iterate through the levels
  local firstLevel = true
  repeat
    if not firstLevel then
      local result, reason = self:completeLevelDown()
      if not result then
        return false, reason
      end
    end
    firstLevel = false

    local result, reason = self:buildCurrentLevel()
    if not result then
      return false, reason
    end
    -- go until we are just about to get to the starting level
  until self.move.posY == self.options.loadedModel.startPoint[3] + 1

  -- button up the last upper level
  local result, reason = self:completeLevelDown()
  if not result then
    return false, reason
  end

  return true
end

function Builder:iterate()
  -- before we begin, do a resupply run.
  local posX = self.move.posX
  local posZ = self.move.posZ
  local dumped = self:dumpInventoryAndResupply()
  if not dumped then
    self.move:moveToXZ(posX, posZ)
    self.move:faceDirection(self.originalOrient)
    return false, "Problem dumping inventory or picking up supplies."
  end
  if not self.move:moveToXZ(posX, posZ) then
    self.move:faceDirection(self.originalOrient)
    return false, "Could not dump inventory, resupply, and return safely."
  end

  local result, reason = self:buildLowerLevels()
  if not result then
    return false, reason
  end
  result, reason = self:buildUpperLevels()
  if not result then
    return false, reason
  end
  result, reason = self:buildCurrentLevel()
  if not result then
    return false, reason
  end

  return true
end

function Builder:applyDefaults() --luacheck: no unused args
  self.options.port = tonumber(self.options.port or "888")
  self.options.trashCobble = self.options.trashCobble == true or self.options.trashCobble == "true"
  self.options.saveState = self.options.saveState == nil or self.options.saveState == true
    or self.options.saveState == "true"
end

function Builder:saveState()
  if self.options.saveState then
    return objectStore.saveObject("builder", self.options)
  end
end

function Builder:loadState()
  local result = objectStore.loadObject("builder")
  if result ~= nil then
    self.options = result
    self:applyDefaults()
    model.prepareState(self.options.loadedModel)
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
  o.eventDispatcher = eventDispatcher.new({ debounce = 10 }, o)
  return o
end

local args, options = shell.parse( ... )
if args[1] == 'help' then
  print("commands: start, resume, summon")
elseif args[1] == 'start' then
  if (args[2] == 'help') then
    print("usage: builder start --model=mymodel.model")
  else
    options.resuming = false
    local b = builder.new({options = options})
    b:applyDefaults()
    b:start()
  end
elseif args[1] == 'resume' then
  options.resuming = true
  local b = builder.new({options = options})
  if b:loadState() then
    b:start()
  else
    print("Cannot resume. Make sure the robot has a writable hard drive to save state in.")
  end
elseif args[1] == 'summon' then
  modem.broadcast(tonumber(options.port or "888"), "return")
end

return builder
