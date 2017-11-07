local mockInv = require("test/ocmocks/mock_inventory")
local sides = require("sides")
local robot = {}
local placeMap = {}

local function setPlacemap(pos, value)
  placeMap[pos.y] = placeMap[pos.y] or {}
  local y = placeMap[pos.y]
  y[pos.x] = y[pos.x] or {}
  local x = y[pos.x]
  x[pos.z] = value
end

robot.placeMap = placeMap

function robot.drawPlacemap()
  for y,level in pairs(placeMap) do
    print("")
    print("LEVEL " .. y)
    print("===========================")

    for x,row in pairs(level) do
      for z,col in pairs(row) do
        print(x,z,col)
      end
    end
  end
end

function robot.detect()
  print("robot: detect")
  return false, "air"
end
function robot.detectUp()
  print("robot: detectUp")
  return false, "air"
end
function robot.detectDown()
  print("robot: detectDown")
  return false, "air"
end
function robot.forward()
  robot.sm:forward()
  print("robot: forward")
  return true
end
function robot.back()
  robot.sm:backward()
  print("robot: back")
  return true
end
function robot.turnLeft()
  robot.sm:turnLeft()
  print("robot: turnLeft")
  return true
end
function robot.turnRight()
  robot.sm:turnRight()
  print("robot: turnRight")
  return true
end
function robot.turnAround()
  robot.sm:turnAround()
  print("robot: turnAround")
  return true
end
function robot.up()
  robot.sm:up()
  print("robot: up")
  --return false
  return true
end
function robot.down()
  robot.sm:down()
  print("robot: down")
  return true
end
function robot.inventorySize()
  return 32
end
function robot.select(slot)
  print("robot: select " .. slot)
  mockInv.selected = slot
end
function robot.count(slot)
  local stack = mockInv.slots[slot or mockInv.selected]
  if not stack then
    return 0
  else
    return stack.size
  end
end
function robot.place()
  local stack = mockInv.get()
  if not stack or stack.size <= 0 then
    print("robot: place (fail)")
    return false, "empty slot"
  end
  stack.size = stack.size - 1
  if stack.size <= 0 then
    mockInv.slots[mockInv.selected] = nil
  end
  print("robot: place " .. stack.name .. "(" .. stack.size .. ") at " .. robot.sm:summary())
  setPlacemap(robot.sm:facing(), 'x')
  return true
end
function robot.placeUp()
  local stack = mockInv.get()
  if not stack or stack.size <= 0 then
    print("robot: placeUp (fail)")
    return false, "empty slot"
  end
  stack.size = stack.size - 1
  if stack.size <= 0 then
    mockInv.slots[mockInv.selected] = nil
  end
  print("robot: placeUp " .. stack.name .. "(" .. stack.size .. ")")
  return true
end
function robot.placeDown()
  local stack = mockInv.get()
  if not stack or stack.size <= 0 then
    print("robot: placeDown (fail)")
    return false, "empty slot"
  end
  stack.size = stack.size - 1
  if stack.size <= 0 then
    mockInv.slots[mockInv.selected] = nil
  end
  print("robot: placeDown " .. stack.name .. "(" .. stack.size .. ")")
  return true
end

function robot.swing()
  print("robot: swing")
  return true
end

function robot.dropDown(count)
  local toDrop = mockInv.get()
  if not toDrop then
    return false
  end
  count = count or toDrop.size

  local i = mockInv.getMockWorldInventory(sides.down)
  if not i then
    return false -- todo: well I guess it could go into the world but i usually dont want that
  end
  for slot=1,#i do
    local stack = i[slot]
    if not stack then
      i[slot] = {name=toDrop.name,size=count}
      toDrop.size = toDrop.size - count
      if toDrop.size <= 0 then
        mockInv.slots[mockInv.selected] = nil
      end
      print("robot: dropDown of " .. toDrop.name .. " (" .. count .. ") success")
      return true
    elseif stack.name == toDrop.name then
      stack.size = stack.size + count
      toDrop.size = toDrop.size - count
      if toDrop.size <= 0 then
        mockInv.slots[mockInv.selected] = nil
      end
      print("robot: dropDown of " .. toDrop.name .. " (" .. count .. ") success")
      return true -- todo: bleed over if stack size > 64
    end
  end
  print("robot: dropDown of " .. toDrop.name .. " (" .. count .. ") failed")
  return false
end

package.preload.robot = function() return robot end
