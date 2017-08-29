local quary = require("quary")
local robot = require("robot")

local q = quary.new({robot = robot, depth = 30, width = 20})
q:start()