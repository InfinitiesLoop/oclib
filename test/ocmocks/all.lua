require("test/ocmocks/event")
require("test/ocmocks/shell")
require("test/ocmocks/component")
require("test/ocmocks/sides")
require("test/ocmocks/robot")
require("test/ocmocks/computer")
require("test/ocmocks/internet")

require("test/ocmocks/mock_inventory")

require("objectStore").baseDir = "/usr/local/oclib/objectstore"

local function noop() return true end

require("robot").sm = require("smartmove").new({
  robot = {
    up = noop,
    down = noop,
    forward = noop,
    back = noop,
    turnLeft = noop,
    turnRight = noop,
    turnAround = noop
  }
})