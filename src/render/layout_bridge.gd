class_name LayoutBridge
extends RefCounted
## Converts sim data (ShipLayout / SimWorld rooms) into the plain dictionaries ShipView consumes.
## Tier convention: sim tiers are 0-based (0 = tier I); art/ShipView tiers are 1-based.


## Rooms of a port-phase layout -> ShipView.set_rooms() input.
static func rooms_from_layout(layout: ShipLayout) -> Array:
	var out: Array = []
	var decks: int = layout.hull.decks
	for r: PlacedRoom in layout.rooms:
		out.append({
			"uid": r.uid,
			"room_id": r.def.id,
			"deck": r.first_deck(),
			"x": r.x,
			"width": r.def.width,
			"tier": r.tier + 1,
			"decks_tall": r.decks_tall(decks),
		})
	return out


## Rooms of a running voyage -> ShipView.set_rooms() input.
static func rooms_from_world(world: SimWorld) -> Array:
	var out: Array = []
	var decks: int = world.grid.hull.decks
	for r: RoomRuntime in world.rooms:
		out.append({
			"uid": r.uid,
			"room_id": r.def.id,
			"deck": 0 if r.def.id == &"elevator" else r.deck,
			"x": r.x,
			"width": r.width,
			"tier": r.tier + 1,
			"decks_tall": r.def.decks_tall(decks),
		})
	return out


## Per-frame visual state of a runtime room for ShipView.set_room_state().
static func room_state(r: RoomRuntime) -> Dictionary:
	return {
		"broken": r.broken,
		"busy_ratio": r.busy_ratio,
		"repair_progress": r.repair_progress,
	}
