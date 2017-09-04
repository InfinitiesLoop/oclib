local component = require("component")
local ic = component.inventory_controller
local robot = require("robot")
local sides = require("sides")
local util = require("util")

local inventory = {}

function inventory.isOneOf(item, checkList)
  for chk in checkList do
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
  for i=fromSlotNumber,robot.inventorySize() do
    local c = robot.count(i)
    if c > 0 then
      local stack = ic.getStackInInternalSlot(i)
      if not inventory.isOneOf(stack, exceptFor) then

        robot.select(i)
        if side == nil or side == sides.front then
          robot.drop()
        elseif side == sides.bottom then
          robot.dropDown()
        elseif side == sides.top then
          robot.dropUp()
        end
        -- see if all the items were successfully dropped
        c = robot.count(i)
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
  for i=1,robot.inventorySize() do
    local stack = ic.getStackInInternalSlot(i)
    if stack ~= nil and string.find(stack.name, pattern) ~= nil then
      robot.select(i)
      return true
    end
  end
  return false
end

function inventory.placeTorch(sideOfRobot, sideOfBlock)
  if inventory.selectItem("torch$") then
    local success
    if sideOfRobot == nil or sideOfRobot == sides.down then
      success = robot.placeDown(sideOfBlock or sides.bottom)
    elseif sideOfRobot == sides.front then
      success = robot.place(sideOfBlock or sides.bottom)
    end
    if success then
      return true
    end
  end
  return false
end

function inventory.isLocalFull()
  -- backwards cuz the later slots fill up last
  for i=robot.inventorySize(),1,-1 do
    local stack = ic.getStackInInternalSlot(i)
    if stack == nil then
      return false
    end
  end
  return true
end

function inventory.toolIsBroken()
  local d = robot.durability()
  d = util.trunc(d or 0, 2)
  return d <= 0
end

function inventory.equipFreshTool()
  -- first we must see what tool it is we currently have
  -- swap it with slot 1
  robot.select(1)
  ic.equip()
  local currentTool = ic.getStackInInternalSlot()
  -- equip it back since whatever was in slot 1 might be important
  ic.equip()

  if currentTool == nil then
    -- no current tool, sorry
    return false
  end

  local itemName = currentTool.name

  for i=1,robot.inventorySize() do
    local stack = ic.getStackInInternalSlot(i)
    if stack ~= nil and stack.name == itemName then
      robot.select(i)
      ic.equip()
      -- found one but we need to check if it's got durability
      if not inventory.toolIsBroken() then
        return true
      end
      -- not durable enough, so put it back and keep looking
      ic.equip()
    end
  end

  return false
end


return inventory