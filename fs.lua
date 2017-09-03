local filesystem = require("component").filesystem
local serializer = require("serializer")

local function saveObject(name, obj)
	if filesystem == nil then return false end
	-- todo
	return true
end

local function loadObject(name)
	if filesystem == nil then return false end
	-- todo
	return false
end

return {
	saveObject = saveObject,
	loadObject = loadObject
}