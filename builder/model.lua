local serializer = require("serializer")

local model = {}

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

  -- first we enumerate each level and convert the raw string that has the block layout
  -- into a richer structure, so that we can attach metadata to each block as needed.
  local etlLevels = {}
  for _,l in ipairs(m.levels) do
    local etlRows = {}
    for _,row in ipairs(l.data) do
      local etlRow = {}
      for blockIndex=1,string.len(row) do
        etlRow[#etlRow + 1] = { block = string.sub(row, blockIndex, blockIndex) }
      end
      etlRows[#etlRows + 1] = etlRow
    end

    -- rows is now the real deal, data is not used
    l.rows = etlRows
    l.data = nil

    -- expand out the levels that have a span
    local span = l.span or 1
    l.span = nil
    for _=1,span do
      etlLevels[#etlLevels + 1] = serializer.clone(l)
    end
  end

  m.levels = etlLevels

  return m
end

return model
