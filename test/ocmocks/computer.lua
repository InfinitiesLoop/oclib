local computer = {}

function computer.energy()
  return 10000
end

function computer.maxEnergy()
  return 10000
end

package.preload.computer = function() return computer end