local component = require("component")
local ic = function() return component.inventory_controller end
local robot = function() return require("robot") end
local sides = require("sides")
local util = require("util")

local inventory = {}

function inventory.isOneOf(item, checkList)
  for _,chk in ipairs(checkList) do
    if chk == "!tool" then
      if item.maxDamage > 0 then
        return true
      end
    elseif string.match(item.name, chk) then
      return true
    end
  end
  return false
end

function inventory.dropAll(side, fromSlotNumber, exceptFor)
  -- tries to drop all the robot's inventory into the storage on the given side
  -- returns true if all if it could be unloaded, false if none or only some could
  --robot.drop([number]) -- Returns true if at least one item was dropped, false otherwise.
  local couldDropAll = true
  exceptFor = exceptFor or {}
  fromSlotNumber = fromSlotNumber or 1
  for i=fromSlotNumber,robot().inventorySize() do
    local c = robot().count(i)
    if c > 0 then
      local stack = ic().getStackInInternalSlot(i)
      if not inventory.isOneOf(stack, exceptFor) then

        robot().select(i)
        if side == nil or side == sides.front then
          robot().drop()
        elseif side == sides.bottom then
          robot().dropDown()
        elseif side == sides.top then
          robot().dropUp()
        end
        -- see if all the items were successfully dropped
        c = robot().count(i)
        if c > 0 then
          -- at least one item couldn't be dropped.
          -- but we keep trying to drop all so we still drop as much as we can.
          couldDropAll = false
        end

      end --isOneOf
    end
  end
  return couldDropAll
end

function inventory.isIdealTorchSpot(x, z)
  local isZ = (z % 7)
  local isX = (x % 12)
  if isZ ~= 0 or (isX ~= 0 and isX ~= 6) then
    return false
  end
  -- we skip every other x torch in the first row,
  -- and the 'other' every other torch in the next row
  local zRow = math.floor(z / 7) % 2
  if (zRow == 0 and isX == 6) or (zRow == 1 and isX == 0) then
    return false
  end
  return true
end

function inventory.selectItem(pattern)
  for i=1,robot().inventorySize() do
    local stack = ic().getStackInInternalSlot(i)
    if stack ~= nil and string.find(stack.name, pattern) ~= nil then
      robot().select(i)
      return true
    end
  end
  return false
end

function inventory.placeTorch(sideOfRobot, sideOfBlock)
  if inventory.selectItem("torch$") then
    local success
    if sideOfRobot == nil or sideOfRobot == sides.down then
      success = robot().placeDown(sideOfBlock or sides.bottom)
    elseif sideOfRobot == sides.front then
      success = robot().place(sideOfBlock or sides.bottom)
    end
    if success then
      return true
    end
  end
  return false
end

function inventory.isLocalFull()
  -- backwards cuz the later slots fill up last
  for i=robot().inventorySize(),1,-1 do
    local stack = ic().getStackInInternalSlot(i)
    if stack == nil then
      return false
    end
  end
  return true
end

function inventory.toolIsBroken()
  local d = robot().durability()
  d = util.trunc(d or 0, 2)
  return d <= 0
end

function inventory.stackIsItem(stack, nameOrPattern)
  return stack ~= nil and (stack.name == nameOrPattern or string.match(stack.name, nameOrPattern))
end

function inventory.pickUpFreshTools(sideOfRobot, toolName)
  sideOfRobot = sideOfRobot or sides.bottom
  local size = ic().getInventorySize(sideOfRobot)
  if size == nil then
    return false
  end

  local count = 0
  for i=1,size do
    local stack = ic().getStackInSlot(sideOfRobot, i)
    -- is this the tool we want and fully repaired?
    if inventory.stackIsItem(stack, toolName) and stack.damage == 0 then
      -- found one, get it!
      robot().select(1) -- select 1 cuz it will fill into an empty slot at or after that
      if not ic().suckFromSlot(sideOfRobot, i) then
        return false
      end
      count = count + 1
    end
  end
  return true, count
end

function inventory.dropBrokenTools(sideOfRobot, toolName)
  sideOfRobot = sideOfRobot or sides.bottom
  local brokenToolsCount = 0
  for i=1,robot().inventorySize() do
    local stack = ic().getStackInInternalSlot(i)

    if inventory.stackIsItem(stack, toolName) then
      -- is this a broken tool?
      local isBroken = util.trunc((stack.maxDamage-stack.damage) / stack.maxDamage, 2) <= 0
      if isBroken then
        brokenToolsCount = brokenToolsCount + 1
        -- drop it
        robot().select(i)
        local result = (sideOfRobot == sides.bottom and robot().dropDown(1)) or
          (sideOfRobot == sides.front and robot().drop(1))
        if not result then
          return false, brokenToolsCount
        end
      end
    end
  end
  -- finally we need to see if the tool we are holding is broken
  robot().select(1)
  ic().equip()
  local stack = ic().getStackInInternalSlot(1)
  if inventory.stackIsItem(stack, toolName) then
    -- is this a broken tool?
    local isBroken = util.trunc((stack.maxDamage-stack.damage) / stack.maxDamage, 2) <= 0
    if isBroken then
      brokenToolsCount = brokenToolsCount + 1
      if not robot().dropDown(1) then
        ic().equip()
        return false, brokenToolsCount
      end
    end
  end
  ic().equip()
  return true, brokenToolsCount
end

function inventory.equipFreshTool(itemName)
  if itemName == nil then
    -- use the currently selected tool as the pattern.
    -- first we must see what tool it is we currently have
    -- swap it with slot 1
    robot().select(1)
    ic().equip()
    local currentTool = ic().getStackInInternalSlot()
    -- equip it back since whatever was in slot 1 might be important
    ic().equip()

    if currentTool == nil then
      -- no current tool, sorry
      return false
    end

    itemName = currentTool.name
  end

  for i=1,robot().inventorySize() do
    local stack = ic().getStackInInternalSlot(i)

    if itemName == "!empty" then
      if stack == nil or (stack.maxDamage == nil or stack.maxDamage == 0) then
        -- found an empty slot or at least something that doesn't use durability
        robot().select(i)
        ic().equip()
        return true
      end
    elseif stack ~= nil and (stack.name == itemName or string.match(stack.name, itemName)) then
      robot().select(i)
      ic().equip()
      -- found one but we need to check if it's got durability
      if not inventory.toolIsBroken() then
        return true
      end
      -- not durable enough, so put it back and keep looking
      ic().equip()
    end
  end

  return false
end


return inventory