# oclib

`oclib` is a suite of utilities and programs for the Minecraft OpenComputers mod.

## builder

`oclib` includes a `builder` program that can command an OpenComputers robot to build any arbitrary structure from a model file the describes its layout.
`builder` can work with very large structures, ensuring the robot returns to its charger when needed, refills on supplies from a provided chest(s), 
desupplies any blocks it had to clear out in the process of building, and can deal with a host of problems that would normally cause problems, such as 
mobs or other entities getting in its way while building. It builds models in a way that guarantees the Robot will always be able to return to its charger,
without being blocked by already-built blocks, for example.

One of the key features of the builder program is that it will not disturb any blocks that are
not part of the model itself. You could build a pathway through a mountain, or even encased in glass or ice, and the surrounding blocks will be completely
untouched. It does this by employing a build algorithm that ensures the robot never needs to venture outside of the model's defined blocks.

It also tries to be memory and disk efficient -- keeping memory usage to an absolute minimum, and only storing the part of the model required for the current
state on disk. Normally, very large models would be much too large to fit into a Robot's limited memory size, and some models are even too large to fit on a
Robot's hard drive! It does this by efficiently dealing with only one level at a time, downloading the level it needs directly off the internet when required.

#### Structure file conversion

A java program is provided that can convert Minecraft structure files, such as those captured by the structure block, into model files that the builder robot
can understand. An example application of this is included, as the `World Tree` model was captured this way.
