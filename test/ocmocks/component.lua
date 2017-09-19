local component = {}

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
  print("component.inventory_controller: getStackInInternalSlot " .. slot)
  return nil
end

local filesystem = {}
component.filesystem = filesystem

function filesystem.makeDirectory(dir)
  os.execute("mkdir -p " .. dir)
  print("component.filesystem: makeDirectory " .. dir)
end

package.preload.component = function() return component end
