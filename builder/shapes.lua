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


local function mengerIterate(grid, d0, wOffset, hOffset, lOffset, material)
  if (d0 == 1) then
    grid[wOffset+1][hOffset+1][lOffset+1] = material
    return
  end

  local d1 = d0/3

  for h = 0, 2 do
    for w = 0, 2 do
      if not ((h == 1) and (w == 1)) then
        for l = 0, 2 do
          if not (((h == 1) and (l == 1)) or ((w == 1) and (l == 1))) then
            -- recursion
            if d0 > 3 then
              mengerIterate(grid, d1, w*d1 + wOffset, h*d1 + hOffset, l*d1 + lOffset, material)
            else
              grid[w + wOffset + 1][h + hOffset + 1][l + lOffset + 1] = material
            end
          end
        end
      end
    end
  end
end

function shapes.mengerSponge(len, material)
  -- start off with solidness
  local grid = {}
  for l=1,len do
    grid[l] = {}
    for r=1,len do
      grid[l][r] = {}
      for c=1,len do
        grid[l][r][c] = ' '
      end
    end
  end

  mengerIterate(grid, len, 0, 0, 0, "x")
  local m = {}
  m.title = "menger_sponge_" .. len
  m.author = "InfinitiesLoop"
  m.mats = { x = material }
  m.levels = {}
  for l=1,len do
    m.levels[l] = {}
    m.levels[l].name = "level " .. l
    m.levels[l].blocks = gridToStr(grid[l])
  end
  return m
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

--for i=28,28 do
--local c = shapes.circle(i)
--print(s.serialize({c=c}))
--end

--local m = shapes.mengerSponge(81, 'x')
local m = shapes.mengerSponge(27, 'x')
print(s.serialize(m))

return shapes