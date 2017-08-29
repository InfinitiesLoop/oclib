local inventory = {}

local function inventory.dropAll(robot, side)
	-- tries to drop all the robot's inventory into the storage on the given side
	-- returns true if all if it could be unloaded, false if none or only some could
	--robot.drop([number]) -- Returns true if at least one item was dropped, false otherwise.
	local couldDropAll = true
	for i=0,robot.inventorySize() do
		robot.select(i)
		local c = robot.count()
		if c > 0 then
			robot.drop()
			-- see if all the items were successfully dropped
			c = robot.count()
			if c > 0 then
				-- at least one item couldn't be dropped.
				-- but we keep trying to drop all so we still drop as much as we can.
				couldDropAll = false
			end
		end
	end
	return couldDropAll
end

return inventory