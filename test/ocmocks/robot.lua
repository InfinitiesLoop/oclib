local robot = {}

function robot.detect()
  return false, "air"
end
function robot.forward()
  print("robot: forward")
  return true
end
function robot.turnLeft()
  print("robot: turnLeft")
  return true
end
function robot.turnRight()
  print("robot: turnRight")
  return true
end
function robot.turnAround()
  print("robot: turnAround")
  return true
end
function robot.up()
  print("robot: up")
  return true
end
function robot.down()
  print("robot: down")
  return true
end

package.preload.robot = function() return robot end
