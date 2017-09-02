local init = {}
local shell = require("shell")

function init.getfiles()
  print("initializing files...")
  local repo
  for line in io.lines(os.getenv("PWD") .. "/init.files") do
    if repo == nil then
      repo = line
      print("repo " .. repo)
    else
      print("getting " .. line)
      os.execute("wget -f https://raw.githubusercontent.com/" .. repo .. "/master/" .. line ..
        "?" .. math.random() .. " " .. line)
    end
  end
  print("done")
end

function init.clone(repo)
  os.execute("wget -f https://raw.githubusercontent.com/" .. repo .. "/master/init.files?"
    .. math.random() .. " init.files")
  init.getfiles()
end

local args = shell.parse( ... )
if args[1] ~= nil then
  init.clone(args[1])
else
  init.getfiles()
end

return init
