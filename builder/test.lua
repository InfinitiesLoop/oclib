local model = require("builder/model")
local serializer = require("serializer")

local simpleHouse = model.load("builder/models/simplehouse.model")

print(type(simpleHouse), simpleHouse)
print(serializer.serialize(simpleHouse))