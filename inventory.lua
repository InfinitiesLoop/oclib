local c = require("component")
local ic = c.inventory_controller
local sides = require("sides")

local inventory = {}

function inventory.dropAll(robot, side)
	-- tries to drop all the robot's inventory into the storage on the given side
	-- returns true if all if it could be unloaded, false if none or only some could
	--robot.drop([number]) -- Returns true if at least one item was dropped, false otherwise.
	local couldDropAll = true
	for i=1,robot.inventorySize() do
		local c = robot.count(i)
		if c > 0 then
			robot.select(i)
			robot.drop()
			-- see if all the items were successfully dropped
			c = robot.count(i)
			if c > 0 then
				-- at least one item couldn't be dropped.
				-- but we keep trying to drop all so we still drop as much as we can.
				couldDropAll = false
			end
		end
	end
	return couldDropAll
end

function inventory.isIdealTorchSpot(x, z)
	local isZ = (z % 7) == 0
	local isX = (x % 24) == 0 or (x % 24) == 11
	if not isZ or not isX then
		return false
	end
	-- we skip every other x torch in the first row,
	-- and the 'other' every other torch in the next row
	local zRow = math.floor(z / 7) % 2
	if (zRow == 0 and isX == 11) or (zRow == 1 and isX == 0) then
		return false
	end 
	return true
end

function inventory.selectItem(robot, name)
	for i=1,robot.inventorySize() do
		local stack = ic.getStackInInternalSlot(i)
		if stack ~= nil and stack.name == name then
			robot.select(i)
			return true
		end
	end
	return false
end

function inventory.placeTorch(robot, side)
	if inventory.selectItem("minecraft:torch") then
		local success, what = robot.use(side or sides.bottom)
		if success and what == 'item_placed' then
			return true
		end
	end
	return false
end

return inventory