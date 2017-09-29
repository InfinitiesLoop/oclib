local _ = require("test/ocmocks/all")

local sides = require("sides")
local model = require("builder/model")
local pathing = require("builder/pathing")
local mockInv = require("test/ocmocks/mock_inventory")
local builder = require("builder/builder")
local inventory = require("inventory")
local s = require("serializer")

--local m = model.load("builder/models/provingground.model")
--local m = model.load("builder/models/simplehouse.model")


--print(s.serialize(m))
--local l = m.levels[1]

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
  size = 64
})
mockInv.slots[1] = {
  name = "minecraft:dirt",
  size = 64
}



mockInv.setMockWorldInventory(sides.bottom, {
  { name = "minecraft:cobblestone", size = 6400 },
  { name = "minecraft:marble", size = 79 },
  { name = "minecraft:glass", size = 64 },
  { name = "minecraft:dirt", size = 64 },
  { name = "minecraft:dirt", size = 64 },
  { name = "minecraft:dirt", size = 64 }
}, 32)

--local counts, hasZero = inventory.resupply(sides.bottom, { cobblestone = 400, glass = 100, marble = 100 }, 200)
--print(s.serialize(counts), hasZero)

--local map = { glass = 0, cobblestone = 0, test = 0, marble = 1000 }
--inventory.setCountOfItems(map)
--print(s.serialize(map))
--print(inventory.getCountOfItems({"cobblestone"}), inventory.getCountOfItems({"glass"}))

local b = builder.new({options = { model = "builder/models/sphere_25.model" } })
b:start()
print(s.serialize(b.options.loadedModel.matCounts))
