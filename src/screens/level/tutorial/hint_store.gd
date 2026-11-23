class_name HintStore
extends RefCounted
## "Seen once" flags for the tutorial and the contextual first-time hints.
##
##   HintStore.for_params(params) -> HintStore   (real runs: user://hints.json; dev runs: memory only so that
##                                                 --selftest / --phase / --nosave never touch the player's file)
##   has(id) -> bool      mark(id)      clear(id)      reset()      shown_count() -> int
##
## The ids used by the game are plain StringNames: &"tutorial" (med_1 walkthrough finished or skipped),
## &"sick", &"ghost", &"event_<event id>", &"elevator", &"tier2", &"queue_anger", &"mutiny", &"dest_<id>".
## NOTE: reset_progress() in SaveManager does not know about this file; call HintStore.wipe_file() from there
## (or the settings panel) if "reset progress" should also bring the hints back.

const PATH: String = "user://hints.json"
const VERSION: int = 1

var path: String = PATH
var persist: bool = true
var _seen: Dictionary = {}


## True for dev / test launches (anything but a plain `--scene=level --level=<id>`): they never touch the player's file.
static func is_dev(params: Dictionary) -> bool:
	return String(params.get("phase", "port")) != "port" or params.has("selftest") or params.has("nosave") \
			or params.has("autobuild") or params.has("sim_seconds") or params.has("autoplay")


## Dev launches only get the tutorial / hints when they ask for them (--tutorial, --tutstep=, --hints, --hint=,
## --selftest=tutorial*), so other people's screenshots and self-tests of med_1 are left alone.
static func asked_for(params: Dictionary) -> bool:
	return params.has("tutorial") or params.has("tutstep") or params.has("hints") or params.has("hint") \
			or String(params.get("selftest", "")).begins_with("tutorial")


static func for_params(params: Dictionary) -> HintStore:
	var s := HintStore.new()
	var dev: bool = is_dev(params)
	if params.has("hints_file"):
		s.path = String(params["hints_file"])
		s.persist = true
	else:
		s.path = PATH
		s.persist = not dev
	if params.has("hints_fresh") and s.persist:
		s._seen.clear()
		s._write()
	elif s.persist:
		s._read()
	return s


func has(id: StringName) -> bool:
	return bool(_seen.get(String(id), false))


func mark(id: StringName) -> void:
	if has(id):
		return
	_seen[String(id)] = true
	_write()


func clear(id: StringName) -> void:
	if _seen.erase(String(id)):
		_write()


func reset() -> void:
	_seen.clear()
	_write()


func shown_count() -> int:
	return _seen.size()


## Deletes the persisted file (used when the player resets their progress).
static func wipe_file() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func _read() -> void:
	_seen.clear()
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return
	var shown: Variant = (json.data as Dictionary).get("shown", {})
	if shown is Dictionary:
		for k: Variant in (shown as Dictionary).keys():
			if bool((shown as Dictionary)[k]):
				_seen[String(k)] = true


func _write() -> void:
	if not persist:
		return
	var tmp: String = path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("HintStore: cannot write %s" % tmp)
		return
	f.store_string(JSON.stringify({"version": VERSION, "shown": _seen}, "\t"))
	f.close()
	var err: Error = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		DirAccess.remove_absolute(path)
		DirAccess.rename_absolute(tmp, path)
