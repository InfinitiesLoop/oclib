local mockInv = require("test/ocmocks/mock_inventory")
local robot = {}

function robot.detect()
  return false, "air"
end
function robot.detectUp()
  return false, "air"
end
function robot.forward()
  print("robot: forward")
  return true
end
function robot.back()
  print("robot: back")
  return true
end
function robot.turnLeft()
  print("robot: turnLeft")
  return true
end
function robot.turnRight()
  print("robot: turnRight")
  return true
end
function robot.turnAround()
  print("robot: turnAround")
  return true
end
function robot.up()
  print("robot: up")
  --return false
  return true
end
function robot.down()
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
function robot.place()
  local stack = mockInv.get()
  if not stack or stack.count <= 0 then
    print("robot: place (fail)")
    return false, "empty slot"
  end
  stack.count = stack.count - 1
  if stack.count <= 0 then
    mockInv.slots[mockInv.selected] = nil
  end
  print("robot: place " .. stack.name .. "(" .. stack.count .. ")")
  return true
end
function robot.placeUp()
  local stack = mockInv.get()
  if not stack or stack.count <= 0 then
    print("robot: placeUp (fail)")
    return false, "empty slot"
  end
  stack.count = stack.count - 1
  if stack.count <= 0 then
    mockInv.slots[mockInv.selected] = nil
  end
  print("robot: placeUp " .. stack.name .. "(" .. stack.count .. ")")
  return true
end

package.preload.robot = function() return robot end
