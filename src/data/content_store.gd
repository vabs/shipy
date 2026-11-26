class_name ContentStore
extends RefCounted
## Static content registry. Loads every .tres under res://data recursively (handles `.remap`).
## Works without the ContentDB autoload (headless scripts, tools). The ContentDB autoload is a thin
## Node wrapper around this class.

const DATA_ROOT: String = "res://data"

static var _loaded: bool = false
static var _rooms: Dictionary = {}
static var _archetypes: Dictionary = {}
static var _staff: Dictionary = {}
static var _events: Dictionary = {}
static var _destinations: Dictionary = {}
static var _hulls: Dictionary = {}
static var _levels: Dictionary = {}


static func ensure_loaded() -> void:
	if not _loaded:
		reload()


static func reload() -> void:
	_rooms = {}
	_archetypes = {}
	_staff = {}
	_events = {}
	_destinations = {}
	_hulls = {}
	_levels = {}
	_scan(DATA_ROOT)
	_loaded = true


static func _scan(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	var files: PackedStringArray = []
	var dirs: PackedStringArray = []
	dir.list_dir_begin()
	var f: String = dir.get_next()
	while f != "":
		if not f.begins_with("."):
			if dir.current_is_dir():
				dirs.append(f)
			else:
				files.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	files.sort()
	dirs.sort()
	for name in files:
		var p: String = path.path_join(name)
		if p.ends_with(".remap"):
			p = p.trim_suffix(".remap")
		if p.ends_with(".tres") or p.ends_with(".res"):
			var res: Resource = load(p)
			if res != null:
				_register(res)
	for d in dirs:
		_scan(path.path_join(d))


static func _register(res: Resource) -> void:
	if res is RoomDef:
		_rooms[(res as RoomDef).id] = res
	elif res is ArchetypeDef:
		_archetypes[(res as ArchetypeDef).id] = res
	elif res is StaffDef:
		_staff[(res as StaffDef).id] = res
	elif res is EventDef:
		_events[(res as EventDef).id] = res
	elif res is DestinationDef:
		_destinations[(res as DestinationDef).id] = res
	elif res is HullDef:
		_hulls[(res as HullDef).id] = res
	elif res is LevelDef:
		_levels[(res as LevelDef).id] = res


static func room(id: StringName) -> RoomDef:
	ensure_loaded()
	return _rooms.get(id) as RoomDef


static func archetype(id: StringName) -> ArchetypeDef:
	ensure_loaded()
	return _archetypes.get(id) as ArchetypeDef


static func staff_role(id: StringName) -> StaffDef:
	ensure_loaded()
	return _staff.get(id) as StaffDef


static func event(id: StringName) -> EventDef:
	ensure_loaded()
	return _events.get(id) as EventDef


static func destination(id: StringName) -> DestinationDef:
	ensure_loaded()
	return _destinations.get(id) as DestinationDef


static func hull(id: StringName) -> HullDef:
	ensure_loaded()
	return _hulls.get(id) as HullDef


static func level(id: StringName) -> LevelDef:
	ensure_loaded()
	return _levels.get(id) as LevelDef


static func levels_for(destination_id: StringName) -> Array[LevelDef]:
	ensure_loaded()
	var out: Array[LevelDef] = []
	for l in _levels.values():
		var lv := l as LevelDef
		if lv.destination == destination_id:
			out.append(lv)
	out.sort_custom(func(a: LevelDef, b: LevelDef) -> bool: return a.index < b.index)
	return out


static func campaign() -> Array[LevelDef]:
	ensure_loaded()
	var out: Array[LevelDef] = []
	for l in _levels.values():
		out.append(l as LevelDef)
	out.sort_custom(func(a: LevelDef, b: LevelDef) -> bool: return a.campaign_index < b.campaign_index)
	return out


static func all_rooms() -> Array[RoomDef]:
	ensure_loaded()
	var out: Array[RoomDef] = []
	for r in _rooms.values():
		out.append(r as RoomDef)
	out.sort_custom(func(a: RoomDef, b: RoomDef) -> bool:
		if a.unlock_level != b.unlock_level:
			return a.unlock_level < b.unlock_level
		return String(a.id) < String(b.id))
	return out


static func all_archetypes() -> Array[ArchetypeDef]:
	ensure_loaded()
	var out: Array[ArchetypeDef] = []
	for a in _archetypes.values():
		out.append(a as ArchetypeDef)
	out.sort_custom(func(a: ArchetypeDef, b: ArchetypeDef) -> bool: return String(a.id) < String(b.id))
	return out


static func all_staff_roles() -> Array[StaffDef]:
	ensure_loaded()
	var out: Array[StaffDef] = []
	for s in _staff.values():
		out.append(s as StaffDef)
	out.sort_custom(func(a: StaffDef, b: StaffDef) -> bool:
		if a.unlock_level != b.unlock_level:
			return a.unlock_level < b.unlock_level
		if a.wage != b.wage:
			return a.wage < b.wage
		return String(a.id) < String(b.id))
	return out


## Crew roles the player may hire while playing the level with this campaign index in this destination.
static func staff_available(campaign_index: int, destination_id: StringName) -> Array[StaffDef]:
	var out: Array[StaffDef] = []
	for s in all_staff_roles():
		if s.is_available(campaign_index, destination_id):
			out.append(s)
	return out


## Roles whose unlock_level is exactly `campaign_index` (what reaching that level newly offers).
static func staff_unlocked_at(campaign_index: int) -> Array[StaffDef]:
	var out: Array[StaffDef] = []
	for s in all_staff_roles():
		if s.unlock_level == campaign_index:
			out.append(s)
	return out


static func all_events() -> Array[EventDef]:
	ensure_loaded()
	var out: Array[EventDef] = []
	for e in _events.values():
		out.append(e as EventDef)
	out.sort_custom(func(a: EventDef, b: EventDef) -> bool: return String(a.id) < String(b.id))
	return out


static func all_destinations() -> Array[DestinationDef]:
	ensure_loaded()
	var out: Array[DestinationDef] = []
	for d in _destinations.values():
		out.append(d as DestinationDef)
	out.sort_custom(func(a: DestinationDef, b: DestinationDef) -> bool: return a.stars_required < b.stars_required)
	return out


static func all_hulls() -> Array[HullDef]:
	ensure_loaded()
	var out: Array[HullDef] = []
	for h in _hulls.values():
		out.append(h as HullDef)
	out.sort_custom(func(a: HullDef, b: HullDef) -> bool: return a.width < b.width)
	return out


## Rooms the player may build while playing the level with this campaign index in this destination.
static func rooms_available(campaign_index: int, destination_id: StringName) -> Array[RoomDef]:
	var out: Array[RoomDef] = []
	for r in all_rooms():
		if r.is_available(campaign_index, destination_id):
			out.append(r)
	return out


## Rooms newly unlocked by reaching `campaign_index` (unlock_level == index) for the destination
## of the level at that index.
static func rooms_unlocked_at(campaign_index: int) -> Array[RoomDef]:
	var out: Array[RoomDef] = []
	for r in all_rooms():
		if r.unlock_level == campaign_index:
			out.append(r)
	return out
