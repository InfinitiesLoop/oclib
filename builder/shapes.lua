local shapes = {}
local s = require("serializer")

local function distance(x, y, ratio)
  return math.sqrt((math.pow(y * ratio, 2)) + math.pow(x, 2))
end

local function filled(x, y, radius, ratio)
  return distance(x, y, ratio) <= radius
end

local function fatfilled(x, y, radius, ratio)
  return filled(x, y, radius, ratio) and not (
           filled(x + 1, y, radius, ratio) and
           filled(x - 1, y, radius, ratio) and
           filled(x, y + 1, radius, ratio) and
           filled(x, y - 1, radius, ratio) and
           filled(x + 1, y + 1, radius, ratio) and
           filled(x + 1, y - 1, radius, ratio) and
           filled(x - 1, y - 1, radius, ratio) and
           filled(x - 1, y + 1, radius, ratio)
        )
end

local function sign(n)
  if n > 0 then return 1 else return -1 end
end

local function gridToStr(g)
  local strGrid = {}
  for r=1,#g do
    local row = g[r]
    strGrid[#strGrid + 1] = ""
    for c=1,#row do
      strGrid[#strGrid] = strGrid[#strGrid] .. row[c]
    end
  end
  return strGrid
end

function shapes.circle(diameter)
  local width_r = diameter / 2
  local height_r = diameter / 2
  local ratio = width_r / height_r
  local maxblocks_x, maxblocks_y


  if diameter % 2 == 0 then
    maxblocks_x = math.ceil(width_r - .5) * 2 + 1
  else
    maxblocks_x = math.ceil(width_r) * 2;
  end

  if diameter % 2 == 0 then
    maxblocks_y = math.ceil(height_r - .5) * 2 + 1
  else
    maxblocks_y = math.ceil(height_r) * 2
  end

  local grid = {}
  for gr=1,diameter do
    grid[#grid+1] = {}
    for gc=1,diameter do
      grid[gr][gc] = "-"
    end
  end

  for y = -maxblocks_y / 2 + 1, maxblocks_y / 2 - 1 do
    for x = -maxblocks_x / 2 + 1, maxblocks_x / 2 - 1 do
          local xfilled =
            fatfilled(x, y, width_r, ratio) and not
              (fatfilled(x + sign(x), y, width_r, ratio) and fatfilled(x, y + sign(y), width_r, ratio));

          if xfilled then
            grid[y + maxblocks_y / 2][x + maxblocks_x / 2] = "x"
          end
          --renderer.add(x, y, xfilled);
    end
  end

  return gridToStr(grid)

end

for i=28,28 do
local c = shapes.circle(i)
print(s.serialize({c=c}))
end

return shapes