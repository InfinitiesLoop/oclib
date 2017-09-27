local computer = {}

function computer.energy()
  return 10000
end

function computer.maxEnergy()
  return 10000
end

function computer.freeMemory()
  return collectgarbage("count")
end
package.preload.computer = function() return computer end