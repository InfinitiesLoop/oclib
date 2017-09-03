local quary = require("quary")
--local robot = require("robot")

local q = quary.new({ options = {depth = 50, width = 200} })
q:start()


-- todo
-- chunk loader?
-- height support?
-- generator? use coal that is found on the way
-- quary command line support, with quary resume command.
-- auto compress cobblestone if crafting upgrade present.
-- FEATURE: torches should go in non-ideal spots if necessary. Basically if it wont get to the next good spot
-- FEATURE: place a ladder if in inventory so humans can explore easily (check if robot can move through ladder
--    blocks tho)
