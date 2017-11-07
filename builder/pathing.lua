local model = require("builder/model")
local pathing = {}

function pathing.findNearestBuildSite(m, l, from)
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

function pathing.reverse(path, actualEndPoint)
  local revPath = {}
  for i=#path,1,-1 do
    revPath[#revPath + 1] = path[i]
  end
  revPath[#revPath + 1] = actualEndPoint
  table.remove(revPath, 1)
  return revPath
end

function pathing.pathFromDropPoint(level, toPoint)
  local path = pathing.pathToDropPoint(level, toPoint)
  if not path then
    return path
  end
  return pathing.reverse(path, toPoint)
end

function pathing.pathToDropPoint(level, fromPoint)
  local targetDropPoint = model.dropPointOf(level._model, level)
  -- trivial cases:
  -- (1) we're already standing on the droppoint
  if model.isSame(targetDropPoint, fromPoint) then
    return {}
  end
  -- (2) the drop point is adjacent to us so just move into it
  if model.isAdjacent(targetDropPoint, fromPoint) then
    return { targetDropPoint }
  end

  -- each block has distance information, so just follow the numbers starting at the destination
  -- and go back. For example, if the destination has distance 7, find the adjacent block that has a 6,
  -- and so on. When we get to 0 we found the source drop point and we have the path.
  local current = fromPoint
  local currentDist = model.distanceAt(level, current)
  local path = { }
  while current do
    local adjs = model.adjacents(level, current)
    local found = false
    local i = 1
    while i <= #adjs and not found do
      local adj = adjs[i]
      local adjDistance = model.distanceAt(level, adj)
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
