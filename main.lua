local quary = require("quary")
local robot = require("robot")

local q = quary.new({depth = 50, width = 200})
q:start()


-- todo
-- chunk loader?
-- height support?
-- generator? use coal that is found on the way
-- quary command line support, with quary resume command.
-- auto compress cobblestone if crafting upgrade present.
