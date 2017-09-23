local event = {}
function event.pull()
  return nil
end

package.preload.event = function() return event end