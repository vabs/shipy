class_name SimRunner
extends RefCounted
## Helpers shared by tests and balance runs: build a world for a level and play it out.


## Runs a level to completion. mode: &"passive" | &"active". Returns the voyage result dictionary
## plus `ticks`.
static func run(level: LevelDef, port: PortState, seed_value: int, mode: StringName, max_seconds: float = 400.0) -> Dictionary:
	var world: SimWorld = port.create_world(seed_value)
	var player := AutoPlayer.new(world, mode, seed_value)
	var n: int = 0
	var max_ticks: int = int(max_seconds / SimConst.TICK)
	while not world.finished and n < max_ticks:
		world.tick(SimConst.TICK)
		player.tick(SimConst.TICK)
		n += 1
	var res: Dictionary = world.result.duplicate()
	res["ticks"] = n
	return res
