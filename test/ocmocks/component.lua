local component = {}
local mockInv = require("test/ocmocks/mock_inventory")
local modem = {}
component.modem = modem

function modem.open(port)
  print("component.modem: port open " .. port)
end

local inventory_controller = {}
component.inventory_controller = inventory_controller

function inventory_controller.equip()
  print("component.inventory_controller: equip")
end
function inventory_controller.getStackInInternalSlot(slot)
  --print("component.inventory_controller: getStackInInternalSlot " .. (slot or "selected"))
  return mockInv.slots[slot or mockInv.selected] or nil
end
function inventory_controller.getInventorySize(side)
  local size = mockInv.getInventorySize(side)
  --print("component.inventory_controller: getInventorySize " .. side .. " returns " .. size)
  return size
end
function inventory_controller.getStackInSlot(side, slot)
  local i = mockInv.getMockWorldInventory(side)
  if not i then
    --print("component.inventory_controller: getStackInSlot " .. side .. " slot " .. slot .. " returns nil")
    return nil
  end
  local stack = i[slot] or nil
  --print("component.inventory_controller: getStackInSlot " .. side .. " slot " .. slot ..
  --  " returns " .. ((stack and stack.size) or "nil"))
  return stack
end
function inventory_controller.suckFromSlot(side, slot, count)
  local i = mockInv.getMockWorldInventory(side)
  if not i then return false end
  local stack = i[slot]
  if not stack then return false end
  print("component.inventory_controller: suckFromSlot " .. side .. " slot " .. slot .. " count " .. (count or -1))
  count = math.min(stack.size, count or -1)
  local newStackSize = stack.size - count
  if mockInv.addStack({name=stack.name,size=count}) then
    stack.size = newStackSize
    if stack.size <= 0 then
      i[slot] = false
    end
    print(" -> sucked " .. count .. " of " .. stack.name)
  else
    print(" -> failed to suck " .. count .. " of " .. stack.name)
  end
end

local filesystem = {}
component.filesystem = filesystem

function filesystem.makeDirectory(dir)
  os.execute("mkdir -p " .. dir)
  print("component.filesystem: makeDirectory " .. dir)
end
function filesystem.remove(path)
  os.execute("rm " .. path)
  print("component.filesystem: rm " .. path)
end

package.preload.component = function() return component end
