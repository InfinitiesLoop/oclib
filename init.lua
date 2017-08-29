local init = {}

function init.getfiles()
  print("initializing files...")
  local repo = nil
  for line in io.lines("init.files") do
    if repo == nil do
      repo = line
      print("repo " .. repo)
    else 
      print("getting " .. line)
      os.execute("wget https://raw.githubusercontent.com/" .. repo .. "/master/" .. line .. " " .. line)
    end
  end
  print("done")
end

function init.clone(repo)
  os.execute("wget https://raw.githubusercontent.com/" .. repo .. "/master/init.files init.files")
end

if arg[1] ~= nil then
  init.clone(arg[1])
end
  
return init
