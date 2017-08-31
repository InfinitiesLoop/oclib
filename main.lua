local quary = require("quary")
local robot = require("robot")

local q = quary.new({depth = 30, width = 200})
q:start()


-- todo
-- make more durable tools
-- script tool repair? not sure if possible. at least tool swapping so I can give it several.
-- detect charge level?
-- chunk loader?
-- height support?
