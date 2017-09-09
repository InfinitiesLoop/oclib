
local function serialize(obj, indent, asArray)
  local s = ""
  indent = indent or ''
  for k,v in pairs(obj) do
    local t = type(v)
    if t == "table" then
      -- what kind of table, one like a list or a like a map?
      if v[1] == nil then
        -- map
        if asArray then
          s = s .. indent .. t .. "="
        else
          s = s .. indent .. k .. ":" .. t .. "="
        end
        s = s .. "{\n" .. serialize(v, indent .. '  ') .. indent .. "}\n"
      else
        -- list
        if asArray then
          s = s .. indent .. "list="
        else
          s = s .. indent .. k .. ":list="
        end
        s = s .. "[\n" .. serialize(v, indent .. '  ', true) .. indent .. "]\n"
      end
    elseif t == "boolean" then
      if asArray then
        s = s .. indent .. t .. "="
      else
        s = s .. indent .. k .. ":" .. t .. "="
      end
      if v then
        s = s .. "true\n"
      else
        s = s .. "false\n"
      end
    else
      if asArray then
        s = s .. indent .. t .. "="
      else
        s = s .. indent .. k .. ":" .. t .. "="
      end
      s = s .. v .. "\n"
    end
  end
  return s
end

local function deserializeFromLines(lines)
  local result = {}
  if #lines == 0 then return result end

  local i = 1
  repeat
    local line = lines[i]
    local indent, k, t, v = string.match(line, '(%s*)([^:%s]+):(.+)=(.*)')
    if t == "string" then
      result[k] = v
    elseif t == "number" then
      result[k] = tonumber(v)
    elseif t == "boolean" then
      result[k] = v == "true"
    elseif t == "table" then
      -- find all the lines containing this nested table
      local tableLines = {}
      repeat
        i = i + 1
        line = lines[i]
        tableLines[#tableLines+1] = line
      until (line == (indent .. "}"))
      table.remove(tableLines, #tableLines)
      result[k] = deserializeFromLines(tableLines)
    end

    i = i + 1
  until i > #lines

  return result
end

local function deserialize(str)
  local lines = {}
  for line in string.gmatch(str, "([^\n]+)") do
    lines[#lines + 1] = line
  end

  return deserializeFromLines(lines)
end

return {
  serialize = serialize,
  deserialize = deserialize,
  deserializeLines = deserializeFromLines,
}