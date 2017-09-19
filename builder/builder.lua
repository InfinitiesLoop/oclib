local eventDispatcher = require("eventDispatcher")
local shell = require("shell")
local objectStore = require("objectStore")
local component = require("component")
local model = require("builder/model")
local pathing = require("builder/pathing")
local smartmove = require("smartmove")
local modem = component.modem
local robot
local ic

local builder = {}
local Builder = {}

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
  self.move.originalOrient = self.move.orient -- just so we know which way to face when shutting down
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
    if not self:gotoNextLevel() then
      return false
    end
  end
  return true
end

function Builder:gotoNextLevel()
  local thisLevel = self.options.loadedModel.levels[self.move.posY]
  local nextLevel = self.options.loadedModel.levels[self.move.posY + 1]
  local path = pathing.pathToDropPoint(thisLevel, nextLevel.dropPoint)

  return self:followPath(path) and self.move:up()
end

function Builder:followPath(path)
  --print("follow path: " .. model.pathStr(path))
  -- follow the given path, clearing blocks if necessary as we go,
  -- and saving the state of those blocks
  for _,p in ipairs(path) do
    --print(model.pointStr(p), self.move.orient)
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
    -- move!
    if not self.move:moveToXZ(-p[1], p[2]) then
      return false, "could not move into " .. model.pointStr(p)
    end
  end
  return true
end

function Builder:backToStart() --luacheck: no unused args
  -- todo: follow path back to droppoint of current level
  -- then drop and do the same for the next level down
  -- until we get to level 1s droppoint
  return false
end

function Builder:iterate()
  if not self:gotoNextBuildLevel() then
    print("Could not get to the next level to build.")
    return self:backToStart()
  end

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
