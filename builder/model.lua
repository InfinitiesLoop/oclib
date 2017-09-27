local serializer = require("serializer")

local model = {}

local magicChars = "().%+-*?[^$"
local magicCharsMap = {}
for i=1,string.len(magicChars) do
  magicCharsMap[string.sub(magicChars, i, i)] = true
end

local function at(arr, rc)
  local s = arr[rc[1]]
  if s == nil then return "-" end

  local result
  if type(s) == "string" then
    result = string.sub(s, rc[2], rc[2])
  else
    result = s[rc[2]]
  end
  if result == "" or result == nil then result = "-" end
  return result
end

local function set(arr, rc, value)
  local str = arr[rc[1]]
  if type(str) == "string" then
    str = string.sub(str, 1, rc[2] - 1) .. value .. string.sub(str, rc[2] + 1)
    arr[rc[1]] = str
  else
    str[rc[2]] = value
  end
  return true
end

local function pointStr(p)
  if p then
    return "(" .. p[1] .. "," .. p[2] .. ")"
  else
    return "(nil)"
  end
end

local function pathStr(path)
  local s = ""
  for _,p in ipairs(path) do
    s = s .. "->" .. pointStr(p)
  end
  return s
end

local function isBuildable(level, point)
  return at(level.blocks, point) ~= "-"
end

local function isComplete(level, point)
  return (not isBuildable(level, point)) or at(level.statuses, point) == "D"
end
local function isClear(level, point)
  if not isBuildable(level, point) then
    return true
  end
  local status = at(level.statuses, point)
  return status == "O" or status == "D"
end

local function blockAt(m, level, point)
  if not isBuildable(level, point) then
    return nil
  end
  local moniker = at(level.blocks, point)
  if moniker == ' ' then
    return "!air"
  end
  return m.mats[moniker] or "!air"
end

local function westOf(point)
  return {point[1], point[2]-1}
end
local function eastOf(point)
  return {point[1], point[2]+1}
end
local function northOf(point)
  return {point[1]-1, point[2]}
end
local function southOf(point)
  return {point[1]+1, point[2]}
end
local function adjacents(l, point)
  local adjs = {}
  local a = westOf(point)
  if isBuildable(l, a) then
    adjs[#adjs + 1] = a
  end
  a = eastOf(point)
  if isBuildable(l, a) then
    adjs[#adjs + 1] = a
  end
  a = northOf(point)
  if isBuildable(l, a) then
    adjs[#adjs + 1] = a
  end
  a = southOf(point)
  if isBuildable(l, a) then
    adjs[#adjs + 1] = a
  end
  return adjs
end

local function identifyStartPoint(m, level)
  for i,row in ipairs(level.blocks) do
    local result = string.find(row, "[v^<>]")
    if result then
      level.startPoint = {i, result, level.num, string.sub(row, result, result)}
      m.startPoint = level.startPoint
      level.dropPoint = {i,result}
      return true
    end
  end
  return false
end

local function identifyDropPointsAbove(m)
  for i=m.startPoint[3]+1,#m.levels do
    local level = m.levels[i]
    local lowerLevel = m.levels[i-1]

    -- find the first buildable block in this level that is over a buildable block of the level below it.
    -- it is that block in which the robot can move from the upper level into the lower one in order to
    -- complete that level, or to navigate back to the start point for recharging.
    local ir = 1
    local found = false
    while ir <= #level.blocks and not found do
      local ic = 1
      while ic <= string.len(level.blocks[ir]) and not found do
        if isBuildable(level, {ir, ic}) and isBuildable(lowerLevel, {ir, ic}) then
          found = {ir, ic}
        end
        ic = ic + 1
      end
      ir = ir + 1
    end

    if not found then
      -- uh oh, this means there's no way for the bot to get from a level to the next one down
      -- without having to break an unbuildable block
      return false, "Drop point not possible on level " .. i
    end

    level.dropPoint = found
  end
  return true
end

local function identifyDropPointsBelow(m)
  for i=1,m.startPoint[3]-1 do
    local level = m.levels[i]
    local upperLevel = m.levels[i+1]

    -- find the first buildable block in this level that is under a buildable block of the level above it.
    -- it is that block in which the robot can move from the lower level into the upper one in order to
    -- complete that level, or to navigate back to the start point for recharging.
    local ir = 1
    local found = false
    while ir <= #level.blocks and not found do
      local ic = 1
      while ic <= string.len(level.blocks[ir]) and not found do
        if isBuildable(level, {ir, ic}) and isBuildable(upperLevel, {ir, ic}) then
          found = {ir, ic}
        end
        ic = ic + 1
      end
      ir = ir + 1
    end

    if not found then
      -- uh oh, this means there's no way for the bot to get from a level to the next one down
      -- without having to break an unbuildable block
      return false, "Drop point not possible on level " .. i
    end

    level.dropPoint = found
  end
  return true
end

local function calculateDistancesForLevelRecurse(l, point, distance)
  set(l.distances, point, distance)

  local up    = northOf(point)
  local down  = southOf(point)
  local left  = westOf(point)
  local right = eastOf(point)
  local upCurrent = at(l.distances, up)
  local downCurrent = at(l.distances, down)
  local leftCurrent = at(l.distances, left)
  local rightCurrent = at(l.distances, right)
  -- my adjacent blocks are distance + 1
  local d = distance + 1
  local recurseUp    = isBuildable(l, up) and (upCurrent == "-" or upCurrent > d) and set(l.distances, up, d)
  local recurseDown  = isBuildable(l, down) and (downCurrent == "-" or downCurrent > d) and set(l.distances, down, d)
  local recurseLeft  = isBuildable(l, left) and (leftCurrent == "-" or leftCurrent > d) and set(l.distances, left, d)
  local recurseRight =isBuildable(l, right) and (rightCurrent == "-" or rightCurrent > d) and set(l.distances, right, d)

  -- its key that we set the values of all our neighbors and THEN recurse into them,
  -- or else paths from our neighbors, which are going to be longer, will be calculated first
  if recurseUp then calculateDistancesForLevelRecurse(l, up, d) end
  if recurseDown then calculateDistancesForLevelRecurse(l, down, d) end
  if recurseRight then calculateDistancesForLevelRecurse(l, right, d) end
  if recurseLeft then calculateDistancesForLevelRecurse(l, left, d) end
end

local function calculateDistances(m)
  -- each level has a drop point from which all building on that level will start, furthest to nearest.
  -- for each level we need to calculate how far away each buildable block point is from
  -- that drop point.
  for _,l in ipairs(m.levels) do
      -- this point has distance 0.
      -- the adjacent ones have +1 of that, do it recursively.
    calculateDistancesForLevelRecurse(l, l.dropPoint, 0)
  end
end

function model.load(path)
  local obj, err = serializer.deserializeFile(path)
  if not obj then
    return nil, err
  end
  return model.fromLoadedModel(obj)
end

function model.fromLoadedModel(m)
  -- here's where we take the raw data that was in the model file
  -- and do some ETL on it to make it easier to deal with. for example,
  -- we shall expand levels with span>1 into multiple copies.
  -- and we shall make several parallel views of each level's row data
  -- that will store different information like completion status and distance
  -- from the drop point.
  local etlLevels = {}
  for lnum,l in ipairs(m.levels) do
    l.distances = {}
    l.statuses = {}

print(lnum .. ": " .. require("computer").freeMemory())
    for i,row in ipairs(l.blocks) do
      -- distances stores how far away each block is from the drop point 
      local distances = {}
      --for x=1,string.len(row) do distances[x] = "?" end
      l.distances[i] = distances
      -- statusRow stores whether the block has been completed or not ('D' for complete, 'O' for
      -- hallowed, '.' for unvisited/unknown)
      -- we use `D` because it kinda stands for 'done' but mainly cuz it's the letter closest to looking like a block
      l.statuses[i] = string.gsub(row, "[^_]", ".")
    end

    -- count how many of each material this level needs
    l.matCounts = {}
    for matKey,matName in pairs(m.mats) do
      local matCount = 0
      for _,blockRow in ipairs(l.blocks) do
        local patternToMatch = matKey
        if magicCharsMap[patternToMatch] then
          patternToMatch = "%" .. patternToMatch
        end
        local _,count = string.gsub(blockRow, patternToMatch, "")
        matCount = matCount + count
      end
      l.matCounts[matName] = matCount
    end

    -- expand out the levels that have a span
    local span = l.span or 1
    l.span = nil
    for _=1,span do
      etlLevels[#etlLevels + 1] = serializer.clone(l)
      etlLevels[#etlLevels].num = #etlLevels
    end

    -- add up total mat cost for the whole model
    m.matCounts = {}
    for _,matName in pairs(m.mats) do
      for _,etlLevel in ipairs(etlLevels) do
        m.matCounts[matName] = (m.matCounts[matName] or 0) + etlLevel.matCounts[matName]
      end
    end

  end

  m.levels = etlLevels

  -- identify where the robot is supposed to start out
  local found = false
  local i = 1
  while not found and i <= #m.levels do
    found = identifyStartPoint(m, m.levels[i])
    i = i + 1
  end
  if not found then
    error("Could not find the robots start point. Be sure there is a level with one of: v, ^, <, >")
  end
  -- identify drop points: where the robot can move from level to level safely
  local result, err = identifyDropPointsAbove(m)
  if not result then
    error(err)
  end
  result, err = identifyDropPointsBelow(m)
  if not result then
    error(err)
  end

  -- determines how far away each block is so they can be built in the right order
  calculateDistances(m)

  -- the robot's starting point by definition is already complete
  set(m.levels[m.startPoint[3]].statuses, m.startPoint, 'D')

  return m
end

function model.topMostIncompleteLevel(m)
  for i=#m.levels,m.startPoint[3]+1,-1 do
    if not m.levels[i].isComplete then
      return m.levels[i]
    end
  end
  return nil
end

function model.bottomMostIncompleteLevel(m)
  for i=1,m.startPoint[3]-1 do
    if not m.levels[i].isComplete then
      return m.levels[i]
    end
  end
  return nil
end

model.westOf = westOf
model.eastOf = eastOf
model.northOf = northOf
model.southOf = southOf
model.adjacents = adjacents
model.isBuildable = isBuildable
model.isComplete = isComplete
model.isClear = isClear
model.set = set
model.at = at
model.pointStr = pointStr
model.pathStr = pathStr
model.blockAt = blockAt

return model
