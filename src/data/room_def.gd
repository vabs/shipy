class_name RoomDef
extends Resource
## Static definition of a room type. Content lives in data/rooms/*.tres (see docs/SPEC.md §4).
## Tier convention used everywhere: tier 0 = base (tier I), 1 = tier II, 2 = tier III.

@export var id: StringName = &""
@export var display_name: String = ""
@export var category: StringName = &"rest"
@export var width: int = 1
@export var capacity: int = 0
@export var service_time: float = 1.0
## need -> amount restored over one full use, e.g. {&"hunger": 85.0}
@export var satisfies: Dictionary = {}
@export var fun_tag: StringName = &""
@export var appeal: float = 1.0
@export var spend: int = 0
@export var cost: int = 0
@export var upkeep: float = 0.0
@export var power: int = 0
@export var water: int = 0
@export var placement: StringName = &"interior"
@export var mess_chance: float = 0.0
@export var breakdown_time: float = 0.0
@export var wear_per_use: float = 0.0
@export var unlock_level: int = 1
@export var destination_lock: StringName = &""
## index 0 = tier II, 1 = tier III: {"cost": int, "capacity_add": int, "speed_mult": float}
@export var tier_bonus: Array[Dictionary] = []
@export var colors: Dictionary = {}
@export var description: String = ""
## Extra (not in SPEC table): chance a finished use makes the guest sick (buffet/restaurant).
@export var sick_chance: float = 0.0


func is_transport() -> bool:
	return category == &"transport"


func is_utility() -> bool:
	return category == &"utility"


func is_stairs() -> bool:
	return id == &"stairs"


func is_elevator() -> bool:
	return id == &"elevator"


## True for rooms guests can walk into to be served (incl. cabin and medbay).
func is_service_room() -> bool:
	return id == &"medbay" or not satisfies.is_empty()


func max_tier() -> int:
	return tier_bonus.size()


func capacity_at(tier: int) -> int:
	var c: int = capacity
	for i in mini(tier, tier_bonus.size()):
		c += int(tier_bonus[i].get("capacity_add", 0))
	return c


func speed_at(tier: int) -> float:
	var s: float = 1.0
	for i in mini(tier, tier_bonus.size()):
		s *= float(tier_bonus[i].get("speed_mult", 1.0))
	return s


func service_time_at(tier: int) -> float:
	return service_time / speed_at(tier)


## Cost to upgrade a room currently at `from_tier` to the next tier, or -1 if not possible.
func upgrade_cost(from_tier: int) -> int:
	if from_tier < 0 or from_tier >= tier_bonus.size():
		return -1
	return int(tier_bonus[from_tier].get("cost", 0))


func health_at(tier: int) -> float:
	return breakdown_time * pow(1.2, float(tier))


## Number of decks the room spans for a hull with `hull_decks` decks.
func decks_tall(hull_decks: int) -> int:
	if is_elevator():
		return hull_decks
	if is_stairs():
		return 2
	return 1


func is_available(campaign_index: int, destination_id: StringName) -> bool:
	if unlock_level > campaign_index:
		return false
	if destination_lock != &"" and destination_lock != destination_id:
		return false
	return true
