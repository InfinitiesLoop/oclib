local serializer = require("serializer")
local internet = require("internet")
local objectStore = require("objectStore")
local os = require("os")
local model = {}

local BLOCK_DND = string.byte('-')

local magicChars = "().%+-*?[^$"
local magicCharsMap = {}
for i=1,string.len(magicChars) do
  magicCharsMap[string.sub(magicChars, i, i)] = true
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
local function clearStatuses()
  objectStore.deleteObject("builder_statuses")
end

local function blocksOf(l)
  local blocksInfo = l._model._downloadedBlocks
  if blocksInfo and blocksInfo.forLevel == l.num then
    return blocksInfo.blocks
  end

  local blocks = l.blocks
  if type(blocks) == "table" then
    return blocks
  elseif blocks == "@internet" then
    -- the blocks for this level are loaded from an internet level file
    -- so download the block list
    -- remove it before downloading, for more memory..
    l._model._downloadedBlocks = nil

    -- download the file...
    print("Downloading blocks for level " .. l.num)
    local data = internet.request("https://raw.githubusercontent.com/" .. l._model.blocksBaseUrl
      .. "/" .. string.format("%03d", l.num) .. "?" .. math.random())
    local chunks = {}
    for chunk in data do
      chunks[#chunks+1] = chunk
    end
    print("Blocks downloaded, parsing...")
    -- convert the raw string content into the array of lines
    blocks = {}
    local allLines = table.concat(chunks, "")
    for line in string.gmatch(allLines, "([^\n]+)") do
      blocks[#blocks+1] = {string.byte(line, 1, string.len(line))}
    end
    print("Blocks have been loaded into memory.")

    l._model._downloadedBlocks = { blocks = blocks, forLevel = l.num }
    return blocks
  end
  error("Could not understand where the blocks are defined for level " .. l.num)
end


local function rawBlockAt(level, point)
  return at(blocksOf(level), point) % 1000
end

local function statusAt(level, point)
  return math.floor(at(blocksOf(level), point) / 1000)
end

local function setStatus(level, point, status)
  local value = rawBlockAt(level, point) + (status * 1000)
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
  if blocks == "@internet" then
    return blocks
  end
  local t = {}
  for _,row in ipairs(blocks) do
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

  -- calculate drop points if not specified already
  for _,l in ipairs(m.levels) do
    if not dropPointOf(l._model, l) then
      identifyDropPoint(l)
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

local function calculateDistancesForLevelIterative(l, startPoint)
  local distances = {}
  local notSet = {}
  local blocks = blocksOf(l)
  print("Calculating distances for level " .. l.num)
  set(distances, startPoint, 0)
  local iterations = 0
  while true do
    iterations = iterations + 1
    local modified = false
    for r=1,#blocks do
      local row = blocks[r]
      for c=1,#row do
        local p = { r, c }
        if isBuildable(l, p) then
          local thisDistance = at(distances, p, notSet)
          if thisDistance ~= notSet then
            local shouldDistance = thisDistance + 1
            -- does this point have a distance and has an adjacent that needs updating?
            local adjs = adjacents(l, p)
            for _,adj in ipairs(adjs) do
              local thatDistance = at(distances, adj, notSet)
              if thatDistance == notSet or thatDistance > shouldDistance then
                modified = true
                set(distances, adj, shouldDistance)
              end
            end
          end -- thisDistance
        end -- isBuildable
      end -- col
    end -- row

    -- we went through every row and col and there no changes necessary,
    -- so we're done here!
    if not modified then
      print("Finished calculating distances for level " .. l.num)
      return distances
    end
    if iterations % 10 == 0 then
      -- this thing takes a while, so we need to yield every now and then
      if os.sleep then
        os.sleep(0)
      end
    end
  end -- while true
end

local function distancesOf(m, l)
  -- we only cache the distances calculations for one level at a time.
  -- because of memory constraints.
  -- it means we might calculate it again and again for levels but
  -- the important thing is it is cached while building a particular level
  if not m._distances or m._distances.forLevel ~= l.num then
    m._distances = nil -- make sure to free the old one, if any, first
    if os.sleep then
      for i=1,10 do os.sleep(0) end
    end
    m._distances = {
      forLevel = l.num,
      distances = calculateDistancesForLevelIterative(l, dropPointOf(m, l))
    }
  end
  return m._distances.distances
end

local function furtherThan(l, points, distance)
  local distances = distancesOf(l._model, l)
  for _,point in ipairs(points) do
    if at(distances, point, -1) > distance and not isComplete(l, point) then
      return point
    end
  end
  return nil
end

local function closerThan(l, points, distance)
  local distances = distancesOf(l._model, l)
  for _,point in ipairs(points) do
    if at(distances, point, 100000) < distance and not isComplete(l, point) then
      return point
    end
  end
  return nil
end

local function markLevelComplete(l)
  l.isComplete = true
  -- after a level is complete we dont need to remember
  -- the blocks on it
  l.blocks = nil
end

local function getFurtherAdjacent(level, pos)
  -- see if any of the adjacent blocks from `pos` are incomplete
  -- and have a larger distance than this pos.
  local distances = distancesOf(level._model, level)
  local curDistance = at(distances, pos, 100000)
  local adjs = adjacents(level, pos)
  return furtherThan(level, adjs, curDistance)
end

local function getCloserAdjacent(level, pos)
  -- see if any of the adjacent blocks from `pos` are incomplete
  -- and have a larger distance than this pos.
  local distances = distancesOf(level._model, level)
  local curDistance = at(distances, pos, -1)
  local adjs = adjacents(level, pos)
  return closerThan(level, adjs, curDistance)
end

model.loadStatuses = loadStatuses
model.saveStatuses = saveStatuses
model.clearStatuses = clearStatuses
model.prepareState = prepareState
model.getCloserAdjacent = getCloserAdjacent
model.getFurtherAdjacent = getFurtherAdjacent
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
model.setStatus = setStatus
model.at = at
model.pointStr = pointStr
model.pathStr = pathStr
model.blockAt = blockAt

return model
