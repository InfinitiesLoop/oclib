local _ = require("test/ocmocks/all")

local model = require("builder/model")
local pathing = require("builder/pathing")
local mockInv = require("test/ocmocks/mock_inventory")
local builder = require("builder/builder")
--local s = require("serializer")

--local m = model.load("builder/models/provingground.model")
local m = model.load("builder/models/simplehouse.model")


--print(s.serialize(m))
local l = m.levels[1]

--print("level layout")
--print(s.serialize(l.blocks))

--print("bot starts at " .. model.pointStr(l.dropPoint))
--print("")
--[[
local currentPoint = l.dropPoint
repeat
  local result = pathing.findNearestBuildSite(l, currentPoint)
  if result then
    local buildPoint = result[1]
    local standPoint = result[2][#result[2] ] or currentPoint
    print("build " .. model.pointStr(buildPoint) .. " stand on " .. model.pointStr(standPoint) ..
      " get there via " .. model.pathStr(result[2]))
    -- mark that slot as complete to pretend the robot did the job
    model.set(l.statuses, buildPoint, 'D')
    currentPoint = standPoint
  else
    print("no points left")
  end
until not result
--]]

mockInv.fillAll({
  name = "minecraft:cobblestone",
  count = 64
})
mockInv.slots[1] = {
  name = "minecraft:glass",
  count = 64
}
mockInv.slots[2] = {
  name = "minecraft:marble",
  count = 64
}

local b = builder.new({options = { model = "builder/models/simplehouse.model" } })
b:start()
