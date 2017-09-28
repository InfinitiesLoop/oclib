local function a(t,...)
  local arg = {...}
  for i=1,#arg do
    table.insert(t, arg[i])
  end
end

local function f(file,...)
  file:write(...)
end

local function serializeToFileRec(file, obj, indent, asArray)
  indent = indent or ''
  if asArray then
    for _,v in ipairs(obj) do
      local t = type(v)
      if t == "table" then
        -- what kind of table, one like a list or a like a map?
        if v[1] == nil then
          -- map
          f(file, indent, t, "={\n")
          serializeToFileRec(file, v, indent .. '  ')
          f(file, indent, "}\n")
        else
          -- list
          f(file, indent, "list=", "[\n")
          serializeToFileRec(file, v, indent .. '  ')
          f(file, indent, "]\n")
        end
      elseif t == "boolean" then
        f(file, indent, t, "=")
        if v then
          f(file, "true\n")
        else
          f(file, "false\n")
        end
      else
        f(file, indent, t, "=", v, "\n")
      end
    end
  else
    for k,v in pairs(obj) do
      local t = type(v)
      if t == "table" then
        -- what kind of table, one like a list or a like a map?
        if v[1] == nil then
          -- map
          f(file, indent, k, ":", t, "={\n")
          serializeToFileRec(file, v, indent .. '  ')
          f(file, indent, "}\n")
        else
          -- list
          f(file, indent, k, ":list=[\n")
          serializeToFileRec(file, v, indent .. '  ', true)
          f(file, indent, "]\n")
        end
      elseif t == "boolean" then
        f(file, indent, k, ":", t, "=")
        if v then
          f(file, "true\n")
        else
          f(file, "false\n")
        end
      else
        f(file, indent, k, ":", t, "=", v, "\n")
      end
    end
  end
  return true
end

local function serializeToFile(filePath, obj)
  local file = io.open(filePath, "w")
  if not file then
    return false
  end
  serializeToFileRec(file, obj)
  file:flush()
  file:close()
  return true
end

local function serialize(obj, indent, asArray, toTable)
  local s = toTable or {}
  indent = indent or ''
  if asArray then
    for _,v in ipairs(obj) do
      local t = type(v)
      if t == "table" then
        -- what kind of table, one like a list or a like a map?
        if v[1] == nil then
          -- map
          a(s, indent, t, "={\n")
          serialize(v, indent .. '  ', nil, s)
          a(s, indent, "}\n")
        else
          -- list
          a(s, indent, "list=", "[\n")
          serialize(v, indent .. '  ', true, s)
          a(s, indent, "]\n")
        end
      elseif t == "boolean" then
        a(s, indent, t, "=")
        if v then
          a(s, "true\n")
        else
          a(s, "false\n")
        end
      else
        a(s, indent, t, "=", v, "\n")
      end
    end
  else
    for k,v in pairs(obj) do
      local t = type(v)
      if t == "table" then
        -- what kind of table, one like a list or a like a map?
        if v[1] == nil then
          -- map
          a(s, indent, k, ":", t, "={\n")
          serialize(v, indent .. '  ', nil, s)
          a(s, indent, "}\n")
        else
          -- list
          a(s, indent, k, ":list=[\n")
          serialize(v, indent .. '  ', true, s)
          a(s, indent, "]\n")
        end
      elseif t == "boolean" then
        a(s, indent, k, ":", t, "=")
        if v then
          a(s, "true\n")
        else
          a(s, "false\n")
        end
      else
        a(s, indent, k, ":", t, "=", v, "\n")
      end
    end
  end
  if toTable then
    return
  else
    return table.concat(s, "")
  end
end

local function deserializeFromLines(lines, asArray)
  local result = {}
  if #lines == 0 then return result end

  local i = 1
  repeat
    local line = lines[i]
    if string.len(line) > 0 then
      local indent, k, t, v
      if asArray then
        indent, t, v = string.match(line, '(%s*)([^=]+)=(.*)')
      else
        indent, k, t, v = string.match(line, '(%s*)([^%s]+):(.+)=(.*)')
      end
      if t == "string" then
        v = v
      elseif t == "number" then
        v = tonumber(v)
      elseif t == "boolean" then
        v = v == "true"
      elseif t == "table" then
        -- find all the lines containing this nested table
        local tableLines = {}
        repeat
          i = i + 1
          line = lines[i]
          tableLines[#tableLines+1] = line
        until (line == (indent .. "}"))
        table.remove(tableLines, #tableLines)
        v = deserializeFromLines(tableLines)
      elseif t == "list" then
        -- find all the lines containing this nested list
        local listLines = {}
        repeat
          i = i + 1
          line = lines[i]
          listLines[#listLines+1] = line
        until (line == (indent .. "]"))
        table.remove(listLines, #listLines)
        v = deserializeFromLines(listLines, true)
      end
      if asArray then result[#result+1] = v else result[k] = v end
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

local function clone(o)
  return deserialize(serialize(o))
end

local function deserializeFile(path)
  local l = io.lines(path)
  if not l then
    return nil, "could not open file"
  end

  local lines = {}
  for line in l do
    lines[#lines+1] = line
  end

  return deserializeFromLines(lines)
end

return {
  serialize = serialize,
  serializeToFile = serializeToFile,
  deserialize = deserialize,
  deserializeLines = deserializeFromLines,
  deserializeFile = deserializeFile,
  clone = clone
}