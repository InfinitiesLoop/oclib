local sides = {}

sides.back = -1
sides.front = 1
sides.left = -2
sides.right = 2
sides.up = 10
sides.down = -10
sides.bottom = -10
sides.top = 10

package.preload.sides = function() return sides end
