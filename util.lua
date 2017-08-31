local computer = require("computer")
local event = require("event")

local function trunc(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return math.floor(num * mult) / mult
end

local function needsCharging(threshold)
  local percentCharge = (computer.energy() / computer.maxEnergy())
  if percentCharge <= threshold then
    return true
  end
  return false
end

local function waitUntilCharge(threshold, maxWaitSeconds)
  maxWaitSeconds = maxWaitSeconds or 300
  while maxWaitSeconds > 0 do
    local percentCharge = (computer.energy() / computer.maxEnergy())
    if (percentCharge >= threshold) then
      return true
    end
    maxWaitSeconds = maxWaitSeconds - 1
    event.pull(1, "_chargewait")
  end
  local percentCharge = (computer.energy() / computer.maxEnergy())
  return percentCharge >= threshold
end

return {
  trunc = trunc,
  needsCharging = needsCharging,
  waitUntilCharge = waitUntilCharge
}