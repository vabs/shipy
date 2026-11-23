class_name ArchetypeDef
extends Resource
## Guest archetype (see docs/SPEC.md §4).

@export var id: StringName = &""
@export var display_name: String = ""
## sun_hat | headband | glasses_3d | headphones
@export var prop: StringName = &"sun_hat"
@export var body_color: Color = Color.WHITE
@export var favorite_tags: Array[StringName] = []
@export var favorite_rooms: Array[StringName] = []
## need name -> decay multiplier (e.g. {&"hunger": 1.5})
@export var decay_mult: Dictionary = {}
## Patience multiplier applied in queues of rooms that are NOT in favorite_rooms.
@export var patience_mult_non_favorite: float = 1.0
## Fun decay multiplier applied while the last fun room used did not carry a favourite tag
## (gamer quirk). 1.0 = no quirk.
@export var off_tag_fun_decay_mult: float = 1.0
@export var quirk_text: String = ""


func likes(room: RoomDef) -> bool:
	if favorite_rooms.has(room.id):
		return true
	return room.fun_tag != &"" and favorite_tags.has(room.fun_tag)
