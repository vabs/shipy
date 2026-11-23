extends Node
## Autoload "ContentDB": loads every .tres under res://data and indexes it by id (docs/SPEC.md §4).
## Thin wrapper around the static ContentStore so headless scripts that do not get autoloads can use
## `ContentStore` directly (or instantiate this script and call `load_all()`).


func _ready() -> void:
	load_all()


func load_all() -> void:
	ContentStore.reload()


func room(id: StringName) -> RoomDef:
	return ContentStore.room(id)


func archetype(id: StringName) -> ArchetypeDef:
	return ContentStore.archetype(id)


func staff_role(id: StringName) -> StaffDef:
	return ContentStore.staff_role(id)


func event(id: StringName) -> EventDef:
	return ContentStore.event(id)


func destination(id: StringName) -> DestinationDef:
	return ContentStore.destination(id)


func hull(id: StringName) -> HullDef:
	return ContentStore.hull(id)


func level(id: StringName) -> LevelDef:
	return ContentStore.level(id)


func levels_for(destination_id: StringName) -> Array[LevelDef]:
	return ContentStore.levels_for(destination_id)


func campaign() -> Array[LevelDef]:
	return ContentStore.campaign()


func all_rooms() -> Array[RoomDef]:
	return ContentStore.all_rooms()


func all_archetypes() -> Array[ArchetypeDef]:
	return ContentStore.all_archetypes()


func all_staff_roles() -> Array[StaffDef]:
	return ContentStore.all_staff_roles()


func all_events() -> Array[EventDef]:
	return ContentStore.all_events()


func all_destinations() -> Array[DestinationDef]:
	return ContentStore.all_destinations()


func all_hulls() -> Array[HullDef]:
	return ContentStore.all_hulls()


func rooms_available(campaign_index: int, destination_id: StringName) -> Array[RoomDef]:
	return ContentStore.rooms_available(campaign_index, destination_id)


func rooms_unlocked_at(campaign_index: int) -> Array[RoomDef]:
	return ContentStore.rooms_unlocked_at(campaign_index)
