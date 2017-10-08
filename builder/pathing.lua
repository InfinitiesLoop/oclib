local model = require("builder/model")
local util = require("util")
local pathing = {}

function pathing.findNearestBuildSite(_, l, from)
  -- the return value is a two-element array where
  -- [1] == the build site point (point for block that should be placed next)
  -- [2] == an array of points that represent the path that should be taken to get to the stand point
  local current = from
  local path = {}
  local first = true
  while true do
    local next = model.getFurtherAdjacent(l, current)
    if not next then
      if first then
        -- this means we couldn't find a build site from here,
        -- which means we're standing on it!
        -- we need to just move into a lower distance adjacent and build here.
        -- if we can't find a lower distance adjacent, then we're already on the
        -- drop point and the level is complete.
        next = model.getCloserAdjacent(l, current)
        if not next then
          return false
        else
          return { current, { next } }
        end
      end
      -- 'current' has no adjacent that needs to be built on
      -- so it is itself the best place to build next.
      -- path should already be set to the way to get to that point,
      -- but we only need to get to the block before it, not _it_,
      -- so just peel off the last one on the list.
      table.remove(path)
      return { current, path }
    else
      -- 'next' has a higher distance and isn't built yet
      current = next
      path[#path+1] = next
    end
    first = false
  end
end

local function findNearestBuildSiteRecr(m, l, from, cameFrom, limitMap)
  -- finds the nearest block to 'from' that needs to be built and is safe to build on without
  -- blocking off any paths to other blocks or to the drop point.
  -- This is tricky, but simple. A block is safe to build on if:
  -- 1. Note the distance that block is from the drop point (already calculated via distances array)
  -- 2. Look at the 4 adjacent blocks (n/e/w/s). If any of them are buildable and not finished yet,
  --    look at their distance from the drop point. If any of them have a higher distance from the drop
  --    point, then the current block is not safe to build on as it might block access to that block.
  --    Follow that block and repeat this process until one is found.
  -- 3. Once one is found, we must also select a 'stand point' for the robot to be when it places that block,
  --    which can simply be any adjacent non-finished buildable block.

  -- the return value is a two-element array where
  -- [1] == the build site point (point for block that should be placed next)
  -- [2] == an array of points that represent the path that should be taken to get to the stand point

  -- the limitMap is used to remember which points this process has visited, so if there are multiple
  -- paths to the same block we dont bother investigating more than one of them.
  if limitMap[from[1]] and limitMap[from[1]][from[2]] then
    -- some other recursion path already visited this spot
    return false
  end
  limitMap[from[1]] = limitMap[from[1]] or {}
  limitMap[from[1]][from[2]] = true

  local thisDistance = model.at(model.distancesOf(m, l), from)
  local adjacents = model.adjacents(l, from)
  local toRecurse = {}
  local standPoint = nil
  local isValid = true
  for _,adj in ipairs(adjacents) do
    local thatDistance = model.at(model.distancesOf(m, l), adj)
    local thatIsComplete = model.isComplete(l, adj)
    if thatDistance > thisDistance and not thatIsComplete then
      -- well, we know THIS block isn't a valid build site.
      toRecurse[#toRecurse + 1] = adj
      isValid = false
    elseif not thatIsComplete then
      -- this point is 'closer' to the droppoint so it's a good place to stand on
      -- when placing this block.
      standPoint = adj
    end
  end
  if isValid and standPoint then
    -- this point didn't have an adjacent incomplete block with a higher distance
    -- so it is safe to build right here
    if cameFrom then
      return { from, { } }
    else
      return { from, { standPoint } }
    end
  elseif #toRecurse == 0 then
    -- this block isnt valid and none of the blocks around it are worth investigating.
    -- perhaps we're standing on the droppoint and there's nothing left to do on this level.
    return false
  else
    local shortest = nil
    -- recurse into the neighbors that have something going on, select the one with shortest path
    for _,adj in ipairs(toRecurse) do
      local adjPath = findNearestBuildSiteRecr(m, l, adj, from, limitMap)
      if adjPath then
        -- is that path to get there shorter than the shorted one we found so far?
        if shortest == nil or #adjPath[2] < #shortest[2] then
          shortest = adjPath
        end
      end
    end
    if shortest then
      if cameFrom then
        -- cool, but the recursed value contains the path from that point,
        -- but we got to here before getting to there, so we gotta insert our point
        local path = util.cloneArray(shortest[2])
        table.insert(path, 1, from)
        return { shortest[1], path }
      else
        return shortest
      end
    end
    return shortest or false
  end
end

function pathing.findNearestBuildSiteOld(m, l, from)
  return findNearestBuildSiteRecr(m, l, from, nil, {})
end

function pathing.reverse(path, actualEndPoint)
  local revPath = {}
  for i=#path,1,-1 do
    revPath[#revPath + 1] = path[i]
  end
  revPath[#revPath + 1] = actualEndPoint
  table.remove(revPath, 1)
  return revPath
end

function pathing.pathFromDropPoint(m, level, toPoint)
  local path = pathing.pathToDropPoint(m, level, toPoint)
  if not path then
    return path
  end
  return pathing.reverse(path, toPoint)
end

function pathing.pathToDropPoint(m, level, fromPoint)
  -- each block has distance information, so just follow the numbers starting at the destination
  -- and go back. For example, if the destination has distance 7, find the adjacent block that has a 6,
  -- and so on. When we get to 0 we found the source drop point and we have the path.
  local current = fromPoint
  local currentDist = model.at(model.distancesOf(m, level), current)
  local path = { }
  while current do
    local adjs = model.adjacents(level, current)
    local found = false
    local i = 1
    while i <= #adjs and not found do
      local adj = adjs[i]
      local adjDistance = model.at(model.distancesOf(m, level), adj)
      if adjDistance < currentDist then
        path[#path + 1] = adj
        current = adj
        currentDist = adjDistance
        found = true
      end
      if (adjDistance == 0) then
        -- oh, we're there. the end.
        return path
      end
      i = i + 1
    end
    if not found then
      -- this happens when we were already standing on the droppoint
      return path
    end
  end
end

return pathing
