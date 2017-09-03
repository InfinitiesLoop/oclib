local init = {}
local shell = require("shell")

function init.getfiles(gotFilesList)
  print("initializing files...")
  local repo
  for line in io.lines(os.getenv("PWD") .. "/init.files") do
    if repo == nil then
      repo = line
      if not gotFilesList then
        -- restart, got file listing that may have changed
        init.clone(repo, true)
        return
      end
      print("repo " .. repo)
    else
      print("getting " .. line)
      os.execute("wget -f https://raw.githubusercontent.com/" .. repo .. "/master/" .. line ..
        "?" .. math.random() .. " " .. line)
    end
  end
  print("done")
end

function init.clone(repo, gotFilesList)
  os.execute("wget -f https://raw.githubusercontent.com/" .. repo .. "/master/init.files?"
    .. math.random() .. " init.files")
  init.getfiles(gotFilesList)
end

local args = shell.parse( ... )
if args[1] ~= nil then
  init.clone(args[1], false)
else
  init.getfiles()
end

return init
