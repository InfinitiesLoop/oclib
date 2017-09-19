local shell = {}

function shell.parse()
  return {}, {}
end

package.preload.shell = function() return shell end
