local inv = {
  slots = {},
  selected = 1
}

function inv.fillAll(stack)
  for i=1,32 do
    inv.slots[i] = { name = stack.name, count = stack.count }
  end
end

function inv.get()
  return inv.slots[inv.selected]
end

return inv