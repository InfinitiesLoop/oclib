local util = require("util")
local smartmove = require("smartmove")
local inventory = require("inventory")
local sides = require("sides")
local shell = require("shell")
local objectStore = require("objectStore")
local component = require("component")
local eventDispatcher = require("eventDispatcher")

-- optional components
local ic
local robot

local modem = component.modem
local quary = {}

local NEEDS_CHARGE_THRESHOLD = 0.1
local FULL_CHARGE_THRESHOLD = 0.95

local Quary = {
}

function Quary:canMine() --luacheck: no unused args
  self.eventDispatcher:doEvents()
  if self.returnRequested then
    print("return was requested by my master")
    return false
  end
  if inventory.toolIsBroken() then
    if not inventory.equipFreshTool(self.toolName) then
      print("lost durability on tool and can't find a fresh one in my inventory!")
      return false
    end
  end
  if inventory.isLocalFull() then
    -- inventory is full but maybe we can dump some trash to make room
    if self.options.trashCobble then
      inventory.trash(sides.bottom, {"cobblestone"})
      -- if it is STILL full then we're done here
      if inventory.isLocalFull() then
        print("inventory is full!")
        return false
      end
    else
      print("inventory is full!")
      return false
    end
  end
  -- todo: use generator if present
  if util.needsCharging(NEEDS_CHARGE_THRESHOLD, self.move:distanceFromStart()) then
    print("charge level is low!")
    return false
  end
  return true
end

function Quary:mineDownLevel()
  -- mine down 3 times. it's ok if the swing fails, might be air
  for i=1,3 do
    robot.swingDown()

    if not self.move:down() then
      print("could not move down: " .. i)
      return false
    end
  end

  self.options.currentHeight = self.options.currentHeight + 3
  self:saveState()

  -- at this point we're in the right position but we haven't mined out the block underneath us
  robot.swingDown()
  return true
end

function Quary:placeTorch()
  if self.options.torches then
    if inventory.isIdealTorchSpot(self.move.posZ, self.move.posX - 1) then
      inventory.placeTorch()
      -- not placing a torch isn't considered an error we need to worry about.
      -- basically, we tried.
    end
  end
end

function Quary:advanceWhileMining(direction, dontPlaceTorch, dontClearCurrent)
  if not self:canMine() then
    return false
  end
  self.move:swing(direction)
  return self.move:advance(direction) and (dontClearCurrent or self:clearCurrent(dontPlaceTorch))
end

function Quary:clearCurrent(dontPlaceTorch)
  if not self:canMine() then
    return false
  end
  robot.swingUp()
  if not self:canMine() then
    return false
  end
  robot.swingDown()
  if not dontPlaceTorch then
    self:placeTorch()
  end
  return true
end

function Quary:findStartingLevel()
  -- we need to movedown 1 level at a time, which is 3 blocks each
  local height = 3
  while height < self.options.currentHeight do
    self.eventDispatcher:doEvents()
    if self.returnRequested then return false end
    for _=1,3 do
      robot.swingDown()
      if not self.move:down() then
        print("could not move down to starting level")
        return false
      end
    end
    height = height + 3
  end
  return true
end

function Quary:findStartingPoint()
  -- go to where we left off vertically
  if not self:findStartingLevel() then
    return false
  end

  local width = 1
  while width < self.options.currentWidth do
    if not self:advanceWhileMining(-2 * self.sideFactor, true, true) then
      return false
    end
    width = width + 1
  end

  return true
end

function Quary:backToStart()
  if self.move:moveToZ(0) and -- try Z movement first as we might on the return of the lane, X is blocked
     self.move:moveToXZ(1, 0) and -- first part of current level
     self.move:moveToY(0) and -- start of quary area
     self.move:moveToX(0) then -- charging station

    if self.returnRequested then
      self.move:faceDirection(1)
      return true
    end

    local dumped = self:dumpInventory()
    if not dumped and inventory.isLocalFull() then
      print("could not dump inventory and my inventory is full.")
      self.move:moveToXYZ(0, 0, 0)
      self.move:faceDirection(1)
      return false
      -- its ok if we couldnt drop inventory if our inventory isn't full anyway
    end

    if not self.move:moveToXZY(0, 0, 0) then
      print("could not dump inventory and return safely.")
      self.move:moveToXZY(0, 0, 0)
      self.move:faceDirection(1)
      return false
    end
  else
    self.move:faceDirection(1)
    print("could not get back to 0,0,0 for some reason")
    return false
  end

  -- just to look nice.
  self.move:faceDirection(1)

  print("waiting for charge...")
  if not util.waitUntilCharge(FULL_CHARGE_THRESHOLD, 600) then
    print("waited a long time and I didn't get charged enough :(")
    return false
  end

  -- get a new tool if needed
  if inventory.toolIsBroken() then
    if not inventory.equipFreshTool(self.toolName) then
      print("could not find a fresh tool to equip!")
      return false
    end
  end

  return true
end

function Quary:dumpInventory()
  while true do
    local result = self.move:findInventory(-2 * self.sideFactor, 5, true, 16)
    if result == nil or result <= 0 then
      return false
    end
    local droppedTools = inventory.dropBrokenTools(sides.bottom, self.toolName)
    local droppedInventory = inventory.dropAll(sides.bottom, 1, {"torch$", "!tool"})
    inventory.pickUpFreshTools(sides.bottom, self.toolName)
    if droppedTools and droppedInventory then
      return true
    end
  end
end

function Quary:iterate()
  if not self:advanceWhileMining(1, true) then
    print("could not enter quary area.")
    return self:backToStart()
  end

  local firstLevel = true

  if not self:findStartingPoint() then
    print("could not get back to where I left off.")
    return self:backToStart()
  end

  -- be sure the starting point is fully taken care of
  if not self:clearCurrent() then
    print("could not clear the starting point")
    return self:backToStart()
  end

  repeat
    -- no need to move down on the first level, robot starts on that level already
    if not firstLevel then
      -- return to the (1,0,_) point for the level we're currently on
      if not self.move:moveToXZ(1, 0) then
        print("failed to return to starting point to begin the next quary level")
        return self:backToStart()
      end
      self.options.currentWidth = 1
      if not self:mineDownLevel() then
        print("failed to mine down to the next level")
        return self:backToStart()
      end
      self:placeTorch()
    end
    firstLevel = false

    -- now do a horizontal slice
    local firstLane = true
    local advanceDirection = 1
    while self.options.currentWidth <= self.options.width do
      if not firstLane then
        -- move to next lane
        if not self:advanceWhileMining(-2 * self.sideFactor) then
          print("failed to enter new lane.")
          return self:backToStart()
        end
        -- we're now actually in the current lane
        self:saveState()
      end
      firstLane = false

      for _=1,self.options.depth-1 do
        if not self:advanceWhileMining(advanceDirection) then
          print("could mine not to end of lane")
          return self:backToStart()
        end
      end

      advanceDirection = -advanceDirection
      self.options.currentWidth = self.options.currentWidth + 1
    end

  until self.options.currentHeight >= self.options.height

  local returnedToStart = self:backToStart()
  return returnedToStart, true
end

function Quary:start()
  -- need these things to actually be here now
  robot = require("robot")
  ic = component.inventory_controller

  modem.open(self.options.port)

  if self.options.side == "right" then
    self.sideFactor = -1
  else
    self.sideFactor = 1
  end

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

  if self.options.chunkloader then
    local result, chunkloader = pcall(function() return component.chunkloader end)
    if result then
      chunkloader.setActive(false)
      if chunkloader.setActive(true) then
        print("chunkloader is active")
      end
    end
  end
  local result
  local isDone
  result, isDone = self:iterate()
  while (result and not isDone and not self.returnRequested) do
    print("headed out again!")
    result, isDone = self:iterate()
  end

  if isDone then
    print("Quary complete.")
  elseif self.returnRequested then
    print("You called, master?")
  elseif not result then
    print("Halting.")
  end

  return isDone or false
end

function Quary:saveState()
  return objectStore.saveObject("quarry", self.options)
end

function Quary:loadState()
  local result = objectStore.loadObject("quarry")
  if result ~= nil then
    self.options = result
    self:applyDefaults()
    return true
  end
  return false
end

function Quary:on_modem_message(localAddr, remoteAddr, port, distance, command) --luacheck: no unused args
  print("received message from " .. remoteAddr .. ", distance of " .. distance .. ": " .. command)
  if command == "return" then
    self.returnRequested = true
    modem.send(remoteAddr, port, "returning")
  end
end

function Quary:applyDefaults()
  self.move = self.move or smartmove.new({ moveTimeout = 60 })
  self.options = self.options or {}
  self.options.width = tonumber(self.options.width or "10")
  self.options.depth = tonumber(self.options.depth or "10")
  self.options.height = tonumber(self.options.height or "3")
  self.options.torches = self.options.torches == true or self.options.torches == "true" or self.options.torches == nil
  self.options.chunkloader = self.options.chunkloader == true or self.options.chunkloader == "true" or
    self.options.chunkloader == nil
  self.options.currentHeight = tonumber(self.options.currentHeight or "3")
  self.options.currentWidth = tonumber(self.options.currentWidth or "1")
  self.options.port = tonumber(self.options.port or "444")
  self.options.side = self.options.side or "left"
  self.options.trashCobble = self.options.trashCobble == true or self.options.trashCobble == "true"
end

function quary.new(o)
  o = o or {}
  setmetatable(o, { __index = Quary })
  o:applyDefaults()
  o.eventDispatcher = eventDispatcher.new({}, o)
  return o
end

local args, options = shell.parse( ... )
if args[1] == 'help' then
  print("commands: start, resume, summon")
elseif args[1] == 'start' then
  if (args[2] == 'help') then
    print("usage: quary start --width=100 --depth=100 --height=9 \
      --torches=true|false --chunkloader=true|false --currentHeight=3 --currentWidth=5 --port=444 \
      --side=left|right --trashCobble=false|true")
  else
    local q = quary.new({options = options})
    q:applyDefaults()
    q:saveState()
    q:start()
  end
elseif args[1] == 'resume' then
  local q = quary.new()
  if q:loadState() then
    q:start()
  else
    print("Cannot resume. Make sure the robot has a writable hard drive to save state in.")
  end
elseif args[1] == 'summon' then
  modem.broadcast(tonumber(options.port or "444"), "return")
end

return quary
