local computer = function() return require("computer") end
local event = function() return require("event") end

local function trunc(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return math.floor(num * mult) / mult
end

local function needsCharging(threshold, distanceFromCharger)
  distanceFromCharger = distanceFromCharger or 0
  local percentCharge = (computer().energy() / computer().maxEnergy())
  -- require additional 1% charge per 15 blocks distance to charger
  if (percentCharge - ((distanceFromCharger / 15) / 100)) <= threshold then
    return true
  end
  return false
end

local function waitUntilCharge(threshold, maxWaitSeconds)
  maxWaitSeconds = maxWaitSeconds or 300
  while maxWaitSeconds > 0 do
    local percentCharge = (computer().energy() / computer().maxEnergy())
    if (percentCharge >= threshold) then
      return true
    end
    event().pull(1, "_chargewait")
    maxWaitSeconds = maxWaitSeconds - 1
  end
  local percentCharge = (computer().energy() / computer().maxEnergy())
  return percentCharge >= threshold
end

local function cloneArray(t)
  local copy = {}
  for i,v in ipairs(t) do
    copy[i] = v
  end
  return copy
end

local function tableKeys(tbl)
  local keys = {}
  for k,_ in pairs(tbl) do
    keys[#keys+1] = k
  end
  return keys
end

return {
  trunc = trunc,
  tableKeys = tableKeys,
  needsCharging = needsCharging,
  waitUntilCharge = waitUntilCharge,
  cloneArray = cloneArray
}
