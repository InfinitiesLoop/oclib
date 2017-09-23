local inv = {
  slots = {},
  selected = 1,
  slotCount = 32
}

local worldInv = {
}

function inv.fillAll(stack)
  for i=1,32 do
    inv.slots[i] = { name = stack.name, size = stack.size }
  end
end

function inv.setMockWorldInventory(side, contents, numSlots)
  worldInv[side] = contents
  if numSlots then
    for i=1,numSlots do
      contents[i] = contents[i] or false
    end
  end
end
function inv.getMockWorldInventory(side)
  return worldInv[side]
end

function inv.get(slot)
  return inv.slots[slot or inv.selected]
end
function inv.addStack(putStack, slot)
  slot = slot or inv.selected
  local stack = inv.get(slot)
  if not stack then
    inv.slots[slot] = {name=putStack.name,size=putStack.size}
    return true
  elseif stack.name == putStack.name then
    stack.size = stack.size + putStack.size
    return true
  else
    if slot < inv.slotCount then
      return inv.addStack(putStack, slot + 1)
    end
    return false
  end
end

function inv.getInventorySize(side)
  local i = worldInv[side]
  if not i then
    return nil, "no inventory"
  else
    return #i
  end
end

return inv