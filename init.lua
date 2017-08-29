local init = {}

function init.getfiles()
  print("initializing files...")
  local repo = nil
  for line in io.lines(os.getenv("PWD") .. "/init.files") do
    if repo == nil then
      repo = line
      print("repo " .. repo)
    else 
      print("getting " .. line)
      os.execute("wget -f https://raw.githubusercontent.com/" .. repo .. "/master/" .. line .. " " .. line)
    end
  end
  print("done")
end

function init.clone(repo)
  os.execute("wget -f https://raw.githubusercontent.com/" .. repo .. "/master/init.files init.files")
  init.getfiles()
end

if arg[1] ~= nil then
  init.clone(arg[1])
end
  
return init
