local c = require("component")
local ic = c.inventory_controller
local robot = require("robot")
local sides = require("sides")

local inventory = {}

function inventory.dropAll(side)
	-- tries to drop all the robot's inventory into the storage on the given side
	-- returns true if all if it could be unloaded, false if none or only some could
	--robot.drop([number]) -- Returns true if at least one item was dropped, false otherwise.
	local couldDropAll = true
	for i=1,robot.inventorySize() do
		local c = robot.count(i)
		if c > 0 then
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

function inventory.selectItem(name)
	for i=1,robot.inventorySize() do
		local stack = ic.getStackInInternalSlot(i)
		if stack ~= nil and stack.name == name then
			robot.select(i)
			return true
		end
	end
	return false
end

function inventory.placeTorch(sideOfRobot, sideOfBlock)
	-- todo: sideOfRobot
	if inventory.selectItem("minecraft:torch") then
		local success = robot.placeDown(sideOfBlock or sides.bottom)
		if success then
			return true
		end
	end
	return false
end

function inventory.isLocalFull()
	-- backwards cuz the later slots fill up last
	for i=robot.inventorySize(),1 do
		local stack = ic.getStackInInternalSlot(i)
		if stack == nil then
			return false
		end
	end
	return true
end

return inventory