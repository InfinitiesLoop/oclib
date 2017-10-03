local serializer = require("serializer")
local internet = require("internet")

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
  elseif str == nil then
    arr[rc[1]] = {}
    arr[rc[1]][rc[2]] = value
  else
    str[rc[2]] = value
  end
  return true
end

local function blocksOf(l)
  local blocks = l.blocks
  if type(blocks) == "table" then
    return blocks
  elseif blocks == "@internet" then
    -- the blocks for this level are loaded from an internet level file
    -- so download the block list, unless its the same as the last one we
    -- have loaded.
    local dlBlocks = l._model._downloadedBlocks
    if dlBlocks and dlBlocks.forLevel == l.num then
      return dlBlocks.blocks
    end
    -- download the file...
    print("Downloading blocks for level " .. l.num)
    local data = internet.request("https://raw.githubusercontent.com/" .. l._model.blocksBaseUrl
      .. "/" .. string.format("%03d", l.num) .. "?" .. math.random() .. " ")
    local chunks = {}
    for chunk in data do
      chunks[#chunks+1] = chunk
    end
    print("Blocks downloaded, parsing...")
    -- convert the raw string content into the array of lines
    blocks = {}
    local allLines = table.concat(chunks, "")
    for line in string.gmatch(allLines, "([^\n]+)") do
      blocks[#blocks+1] = line
    end
    print("Blocks have been loaded into memory.")

    l._model._downloadedBlocks = { blocks = blocks, forLevel = l.num }
    return blocks
  end
  error("Could not understand where the blocks are defined for level " .. l.num)
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
  return at(blocksOf(level), point) ~= "-"
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
  local moniker = at(blocksOf(level), point)
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
  for i,row in ipairs(blocksOf(level)) do
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

local function identifyDropPointAbove(level, lowerLevel)
  -- find the first buildable block in this level that is over a buildable block of the level below it.
  -- it is that block in which the robot can move from the upper level into the lower one in order to
  -- complete that level, or to navigate back to the start point for recharging.
  local ir = 1
  local found = false
  local blocks = blocksOf(level)
  while ir <= #blocks and not found do
    local ic = 1
    while ic <= string.len(blocks[ir]) and not found do
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
    return false, "Drop point not possible on level " .. level.num
  end

  level.dropPoint = found
  return true
end

local function identifyDropPointBelow(level, upperLevel)
  -- find the first buildable block in this level that is under a buildable block of the level above it.
  -- it is that block in which the robot can move from the lower level into the upper one in order to
  -- complete that level, or to navigate back to the start point for recharging.
  local ir = 1
  local found = false
  local blocks = blocksOf(level)
  while ir <= #blocks and not found do
    local ic = 1
    while ic <= string.len(blocks[ir]) and not found do
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
    return false, "Drop point not possible on level " .. level.num
  end

  level.dropPoint = found
  return true
end

local function identifyDropPoint(m, l)
  local result, reason
  if l.lowerLevel then
    result, reason = identifyDropPointBelow(l, m.levels[l.num + 1])
  elseif l.num == m.startPoint[3] then
    l.dropPoint = m.startPoint
    result = true
  else
    result, reason = identifyDropPointAbove(l, m.levels[l.num - 1])
  end
  if not result then
    error(reason)
  end
end

local function calculateDistancesForLevelIterative(l, startPoint)
  local distances = {}
  local queue = { {0,startPoint} }
  local queueLen = 1
  while queueLen > 0 do
    local pointInfo = table.remove(queue)
    queueLen = queueLen - 1
    local point = pointInfo[2]
    local distance = pointInfo[1]

    set(distances, point, distance)

    local adjs = adjacents(l, point)
    local d = distance + 1
    for _,adj in ipairs(adjs) do
      local current = at(distances, adj)
      if current == "-" or current > d then
        set(distances, adj, d)
        table.insert(queue, 1, {d,adj})
        queueLen = queueLen + 1
      end
    end
  end

  return distances
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
  local etlLevels = {}
  print("Loading levels...")
  for _,l in ipairs(m.levels) do
    l.statuses = {}
    l._model = m

    -- count how many of each material this level needs
    if not l.matCounts then
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
    end

    -- expand out the levels that have a span
    local span = l.span or 1
    l.span = nil
    if span > 1 then
      for _=1,span do
        etlLevels[#etlLevels + 1] = serializer.clone(l)
        etlLevels[#etlLevels].num = #etlLevels
      end
    else
      etlLevels[#etlLevels + 1] = l
      l.num = #etlLevels
    end
  end

  m.levels = etlLevels

  -- add up total mat cost for the whole model
  m.matCounts = {}
  for _,matName in pairs(m.mats) do
    for _,etlLevel in ipairs(etlLevels) do
      m.matCounts[matName] = (m.matCounts[matName] or 0) + etlLevel.matCounts[matName]
    end
  end

  -- identify where the robot is supposed to start out
  if not m.startPoint then
    local found = false
    local i = 1
    while not found and i <= #m.levels do
      found = identifyStartPoint(m, m.levels[i])
      i = i + 1
    end
    if not found then
      error("Could not find the robots start point. Be sure there is a level with one of: v, ^, <, >")
    end
  end

  -- flag levels below the starting level as 'lower levels'
  for lnum = 1, m.startPoint[3]-1 do
    m.levels[lnum].lowerLevel = true
  end

  -- the robot's starting point by definition 'open'
  set(m.levels[m.startPoint[3]].statuses, m.startPoint, 'O')

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

local function dropPointOf(m, l)
  if l.dropPoint then
    return l.dropPoint
  else
    identifyDropPoint(m, l)
    return l.dropPoint
  end
end

local function distancesOf(m, l)
  -- we only cache the distances calculations for one level at a time.
  -- because of memory constraints.
  -- it means we might calculate it again and again for levels but
  -- the important thing is it is cached while building a particular level
  if not m._distances or m._distances.forLevel ~= l.num then
    m._distances = nil -- make sure to free the old one, if any, first
    m._distances = {
      forLevel = l.num,
      distances = calculateDistancesForLevelIterative(l, dropPointOf(m, l))
    }
  end
  return m._distances.distances
end

local function markLevelComplete(l)
  l.isComplete = true
  -- after a level is complete we dont need to remember
  -- the blocks on it or its status array.
  l.blocks = nil
  l.statuses = nil
end

model.markLevelComplete = markLevelComplete
model.dropPointOf = dropPointOf
model.distancesOf = distancesOf
model.blocksOf = blocksOf
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
