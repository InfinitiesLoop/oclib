local event = {}
function event.foo()
end

package.preload.event = function() return event end