local serializer = require("serializer")
local internet = require("internet")
local objectStore = require("objectStore")
local os = require("os")
local bit32 = require("bit32")
local model = {}

local BLOCK_DND = string.byte('-')

local magicChars = "().%+-*?[^$"
local magicCharsMap = {}
for i=1,string.len(magicChars) do
  magicCharsMap[string.sub(magicChars, i, i)] = true
end

local function isSame(a, b)
  return a[1] == b[1] and a[2] == b[2]
end

local function isAdjacent(a, b)
  return (a[1] == b[1] and math.abs(a[2]-b[2]) == 1) or
    (a[2] == b[2] and math.abs(a[1]-b[1]) == 1)
end

local function at(arr, rc, defaultValue)
  local s = arr[rc[1]]
  if s == nil then return (defaultValue or BLOCK_DND) end

  local result
  if type(s) == "string" then
    result = string.sub(s, rc[2], rc[2])
  else
    result = s[rc[2]]
  end
  if result == "" or result == nil then result = (defaultValue or BLOCK_DND) end
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

local function loadStatuses(l)
  -- first delete so we can free up memory
  l._model._downloadedBlocks = nil
  l._model._downloadedBlocks = objectStore.loadObject("builder_statuses")
end
local function saveStatuses(l)
  if l._model._downloadedBlocks then
    objectStore.saveObject("builder_statuses", l._model._downloadedBlocks)
  elseif type(l.blocks) == 'table' then
    objectStore.saveObject("builder_statuses", { blocks = l.blocks, forLevel = l.num })
  end
end
local function clearStatuses(isNewBuild)
  objectStore.deleteObject("builder_statuses")
  if isNewBuild then
    objectStore.deleteObject("builder_statuses_startlevel")
  end
end

local function blocksOf(l)
  local blocksInfo = l._model._downloadedBlocks
  if blocksInfo and blocksInfo.forLevel == l.num then
    return blocksInfo.blocks
  end

  local blocks = l.blocks
  if type(blocks) == "table" then
    return blocks
  elseif blocks == "@github" or blocks == "@internet" or not blocks then

    if l.num == l._model.startPoint[3] then
      local result = objectStore.loadObject("builder_statuses_startlevel")
      if result ~= false then
        l._model._downloadedBlocks = result
        return result.blocks
      end
    end

    -- the blocks for this level are loaded from an internet level file
    -- so download the block list
    -- remove it before downloading, for more memory..
    l._model._downloadedBlocks = nil
    -- yield to help gc?
    if os.sleep then
      for _=1,10 do os.sleep(0) end
    end

    -- download the file...
    print("Downloading blocks for level " .. l.num)
    local data = internet.request("https://raw.githubusercontent.com/" .. l._model.blocksBaseUrl
      .. "/" .. string.format("%03d", l.num) .. "?" .. math.random())
    local tmpFile = io.open("/tmp/builder_model_tmp", "w")
    for chunk in data do
      tmpFile:write(chunk)
    end
    tmpFile:flush()
    tmpFile:close()
    print("Blocks downloaded, parsing...")
    if os.sleep then
      os.sleep(0)
    end
    -- convert the raw string content into the array of lines
    blocks = {}
    tmpFile = io.lines("/tmp/builder_model_tmp")
    local n = 0
    for line in tmpFile do
      n = n + 1
      blocks[#blocks+1] = {string.byte(line, 1, string.len(line))}
      if n % 10 == 0 then
        if os.sleep then
          os.sleep(0)
        end
      end
    end
    print("Blocks have been loaded into memory.")
    os.remove("/tmp/builder_model_tmp")

    l._model._downloadedBlocks = { blocks = blocks, forLevel = l.num }
    model.calculateDistancesForLevelIterative(l, model.dropPointOf(l._model, l))

    if l.num == l._model.startPoint[3] then
      objectStore.saveObject("builder_statuses_startlevel", l._model._downloadedBlocks)
    end

    return blocks
  end
  print("Could not understand where the blocks are defined for level " .. l.num)
  print(serializer.serialize(l))
  error("Cannot load level " .. l.num)
end


local function rawBlockAt(level, point)
  return bit32.extract(at(blocksOf(level), point), 0, 8) -- bits 0-7
end

local function statusAt(level, point)
  local nope = {}
  local val = at(blocksOf(level), point, nope)
  if val == nope then return BLOCK_DND end
  return bit32.extract(val, 8, 2) -- bits 8-9
end

local function distanceAt(level, point, defaultValue)
  -- do we _have_ a distance for this point?
  local val = at(blocksOf(level), point, defaultValue)
  if val == defaultValue then return defaultValue end
  if bit32.extract(val, 10, 1) ~= 1 then
    return defaultValue
  end
  -- extract distance
  val = bit32.extract(val, 11, 21) -- bits 11-31
  return val
end

local function setStatus(level, point, status)
  local value = bit32.replace(at(blocksOf(level), point), status, 8, 2)
  set(blocksOf(level), point, value)
end

local function setDistance(level, point, dist)
  local value = bit32.replace(at(blocksOf(level), point), dist, 11, 21) -- set dist
  value = bit32.replace(value, 1, 10, 1) -- hasDistance=true
  set(blocksOf(level), point, value)
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
  return rawBlockAt(level, point) ~= BLOCK_DND
end

local function isComplete(level, point)
  return (not isBuildable(level, point)) or statusAt(level, point) == 2
end
local function isClear(level, point)
  if not isBuildable(level, point) then
    return true
  end
  local status = statusAt(level, point)
  return status == 1 or status == 2
end
--local function isNavigatable(level, point)
--end

local function blockAt(m, level, point)
  if not isBuildable(level, point) then
    return nil
  end
  local moniker = rawBlockAt(level, point)
  if moniker == BLOCK_DND then
    return "!air"
  end
  return m.mats[string.char(moniker)] or "!air"
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

local function dropPointOf(m, l)
  if m.startPoint[3] == l.num then
    return m.startPoint
  else
    return l.dropPoint or m.defaultDropPoint
  end
end

local function identifyStartPoint(m, level)
  for r,row in ipairs(blocksOf(level)) do
    for c,col in ipairs(row) do
      local result = string.char(col)
      if result == 'v' or result == '^' or result == '<' or result == '>' then
        level.startPoint = {r, c, level.num, result}
        m.startPoint = level.startPoint
        level.dropPoint = {r,c}
        return true
      end
    end
  end
  return false
end

local function identifyDropPointAbove(level, lowerLevel)
  -- find the first buildable block in this level that is over a buildable block of the level below it.
  -- it is that block in which the robot can move from the upper level into the lower one in order to
  -- complete that level, or to navigate back to the start point for recharging.
  local blocks = blocksOf(level)
  local lowerBlocks = blocksOf(lowerLevel)
  for r,row in ipairs(blocks) do
    for c,_ in ipairs(row) do
      if at(blocks, {r, c}) ~= BLOCK_DND and at(lowerBlocks, {r, c}) ~= BLOCK_DND then
        level.dropPoint = {r, c}
        return true
      end
    end
  end
  -- uh oh, this means there's no way for the bot to get from a level to the next one down
  -- without having to break an unbuildable block
  return false, "Drop point not possible on level " .. level.num
end

local function identifyDropPointBelow(level, upperLevel)
  -- find the first buildable block in this level that is under a buildable block of the level above it.
  -- it is that block in which the robot can move from the lower level into the upper one in order to
  -- complete that level, or to navigate back to the start point for recharging.
  local blocks = blocksOf(level)
  local upperBlocks = blocksOf(upperLevel)
  for r,row in ipairs(blocks) do
    for c,_ in ipairs(row) do
      if at(blocks, {r, c}) ~= BLOCK_DND and at(upperBlocks, {r, c}) ~= BLOCK_DND then
        level.dropPoint = {r, c}
        return true
      end
    end
  end
  -- uh oh, this means there's no way for the bot to get from a level to the next one down
  -- without having to break an unbuildable block
  return false, "Drop point not possible on level " .. level.num
end

local function identifyDropPoint(l)
  local result, reason
  local m = l._model
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

function model.load(path)
  local obj, err = serializer.deserializeFile(path)
  if not obj then
    return nil, err
  end
  return model.fromLoadedModel(obj)
end

local function convertBlocks(blocks)
  if blocks == "@github" then
    return blocks
  end
  local t = {}
  for r=1,#blocks do
    local row = blocks[r]
    t[#t + 1] = {string.byte(row, 1, string.len(row))}
  end
  return t
end
function model.fromLoadedModel(m)
  -- here's where we take the raw data that was in the model file
  -- and do some ETL on it to make it easier to deal with. for example,
  -- we shall expand levels with span>1 into multiple copies.
  local etlLevels = {}
  print("Loading levels...")
  for _,l in ipairs(m.levels) do
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

    -- convert the blocks from an ascii layout to a numeric table based one
    l.blocks = convertBlocks(l.blocks)

    -- expand out the levels that have a span
    local span = l.span or 1
    l.span = nil
    if span > 1 then
      for _=1,span do
        local cloneLevel = serializer.clone(l)
        cloneLevel._model = l._model
        etlLevels[#etlLevels + 1] = cloneLevel
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
      m.matCounts[matName] = (m.matCounts[matName] or 0) + (etlLevel.matCounts[matName] or 0)
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

  -- calculate drop points if not specified already
  for _,l in ipairs(m.levels) do
    if not dropPointOf(l._model, l) then
      identifyDropPoint(l)
    end
  end

  -- preloaded level block info can have distances set
  for _,l in ipairs(m.levels) do
    if l.blocks ~= "@github" then
      model.calculateDistancesForLevelIterative(l, model.dropPointOf(l._model, l))
    end
  end

  return m
end

local function prepareState(m)
  for _,l in ipairs(m.levels) do
    l._model = m
  end
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

local function adjacents(l, point, notWest)
  local adjs = {}
  local a
  if not notWest then
    a = westOf(point)
    if isBuildable(l, a) then
      adjs[#adjs + 1] = a
    end
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

local function calculateDistancesForLevelIterative(l, startPoint)
  local distances = {}
  local queue = { startPoint }
  local queueLen = 1
  setDistance(l, startPoint, 0)

  while queueLen > 0 do
    local point = table.remove(queue)
    queueLen = queueLen - 1
    local distance = distanceAt(l, point)

    local adjs = adjacents(l, point)
    local d = distance + 1
    for a=1,#adjs do
      local adj = adjs[a]
      local current = distanceAt(l, adj, -1)
      if current == -1 or current > d then
        setDistance(l, adj, d)
        table.insert(queue, 1, adj)
        queueLen = queueLen + 1
      end
    end
  end
  return distances
end

local function furtherThan(l, points, distance)
  for i=1,#points do
    local point = points[i]
    if distanceAt(l, point, -1) > distance and not isComplete(l, point) then
      return point
    end
  end
  return nil
end

local function closerThan(l, points, distance)
  for i=1,#points do
    local point = points[i]
    if distanceAt(l, point, 100000) < distance and not isComplete(l, point) then
      return point
    end
  end
  return nil
end

local function markLevelComplete(l)
  l.isComplete = true
end

local function getFurtherAdjacent(level, pos)
  -- see if any of the adjacent blocks from `pos` are incomplete
  -- and have a larger distance than this pos.
  local curDistance = distanceAt(level, pos, 100000)
  local adjs = adjacents(level, pos)
  return furtherThan(level, adjs, curDistance)
end

local function getCloserAdjacent(level, pos)
  -- see if any of the adjacent blocks from `pos` are incomplete
  -- and have a larger distance than this pos.
  local curDistance = distanceAt(level, pos, -1)
  local adjs = adjacents(level, pos)
  return closerThan(level, adjs, curDistance)
end

model.isAdjacent = isAdjacent
model.isSame = isSame
model.calculateDistancesForLevelIterative = calculateDistancesForLevelIterative
model.loadStatuses = loadStatuses
model.saveStatuses = saveStatuses
model.clearStatuses = clearStatuses
model.prepareState = prepareState
model.getCloserAdjacent = getCloserAdjacent
model.getFurtherAdjacent = getFurtherAdjacent
model.markLevelComplete = markLevelComplete
model.dropPointOf = dropPointOf
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
model.setStatus = setStatus
model.statusAt = statusAt
model.distanceAt = distanceAt
model.at = at
model.pointStr = pointStr
model.pathStr = pathStr
model.blockAt = blockAt

return model
