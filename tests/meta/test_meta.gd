extends SceneTree
## Headless tests for the audio & meta layer (Settings, SaveManager, AudioManager, synthesis).
##
##   godot --headless --path . --script res://tests/meta/test_meta.gd
##
## Prints `META TESTS PASSED` (exit 0) or the failures and `META TESTS FAILED` (exit 1).
## Autoloads are not instantiated under --script, so the scripts are loaded and created here with
## temporary file paths under user://__test_meta/ (cleaned up at the end).

const SU := preload("res://src/audio/synth_util.gd")
const SfxBank := preload("res://src/audio/sfx_bank.gd")
const MusicBank := preload("res://src/audio/music_bank.gd")
const SaveScript := preload("res://src/meta/save_manager.gd")
const SettingsScript := preload("res://src/meta/settings.gd")
const AudioScript := preload("res://src/audio/audio_manager.gd")

const DIR: String = "user://__test_meta"

var _fails: Array[String] = []
var _checks: int = 0


## Minimal stand-in for ContentDB (duck-typed, the way SaveManager consumes it).
class FakeDB:
	extends RefCounted
	func campaign() -> Array:
		var out: Array = []
		var dests: Array[String] = ["med", "arctic", "underworld"]
		for d in dests.size():
			for i in range(1, 4):  # only 3 levels per destination in this fake world
				out.append({"id": "%s_%d" % [dests[d], i], "destination": dests[d], "index": i, "campaign_index": d * 3 + i})
		return out
	func destination(id: StringName) -> Variant:
		match id:
			&"med": return {"stars_required": 0, "display_name": "Fake Med"}
			&"arctic": return {"stars_required": 3, "display_name": "Fake Arctic"}
			&"underworld": return {"stars_required": 5, "display_name": "Fake Underworld"}
		return null
	func all_rooms() -> Array:
		return [
			{"id": "cabin", "unlock_level": 1, "destination_lock": ""},
			{"id": "laser", "unlock_level": 2, "destination_lock": ""},
			{"id": "igloo", "unlock_level": 4, "destination_lock": "arctic"},
		]


## All SPEC §5 signals, for binding tests.
class FakeSim:
	extends RefCounted
	signal guest_boarded(guest_id: int)
	signal guest_stormed_off(guest_id: int)
	signal guest_patience_out(guest_id: int, room_uid: int)
	signal guest_slipped(guest_id: int)
	signal guest_got_sick(guest_id: int)
	signal guest_cured(guest_id: int)
	signal room_used(room_uid: int, guest_id: int, spend: int)
	signal room_broken(room_uid: int)
	signal room_repaired(room_uid: int)
	signal mess_spawned(mess_id: int)
	signal mess_cleaned(mess_id: int)
	signal ghost_spawned(ghost_id: int)
	signal ghost_banished(ghost_id: int)
	signal event_started(event_id: StringName)
	signal event_ended(event_id: StringName)
	signal wave_started(wave_index: int, count: int)
	signal money_changed(money: int, delta: int, reason: StringName)
	signal mutiny_warning(seconds_left: float)
	signal mutiny_cleared()
	signal voyage_ended(result: Dictionary)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_test_save_basics()
	_test_save_progression()
	_test_save_persistence()
	_test_save_corrupt()
	_test_save_unlock_all()
	_test_save_content_provider()
	await _test_settings()
	_test_save_with_real_content()
	_test_synth_helpers()
	_test_music_data()
	_test_sfx_synthesis()
	await _test_audio_manager()
	_cleanup()
	print("%d checks" % _checks)
	if _fails.is_empty():
		print("META TESTS PASSED")
		quit(0)
	else:
		for f in _fails:
			print("FAIL: ", f)
		print("META TESTS FAILED")
		quit(1)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(msg)


func _eq(actual: Variant, expected: Variant, msg: String) -> void:
	_checks += 1
	if actual != expected:
		_fails.append("%s (got %s, expected %s)" % [msg, str(actual), str(expected)])


func _sorted_strings(a: Array) -> Array:
	var out: Array = []
	for v in a:
		out.append(String(v))
	out.sort()
	return out


## A content provider with no methods: forces SaveManager onto its built-in SPEC defaults even if
## the real ContentDB autoload exists.
class EmptyDB:
	extends RefCounted


func _new_save(file: String = "save.json") -> Node:
	var sm: Node = SaveScript.new()
	sm.save_path = "%s/%s" % [DIR, file]
	sm.content = EmptyDB.new()
	return sm


func _rm(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _cleanup() -> void:
	for f in ["save.json", "save.json.tmp", "save.json.corrupt", "rt.json", "settings.json", "settings.json.tmp", "bad.json", "s2.json"]:
		_rm("%s/%s" % [DIR, f])
	DirAccess.remove_absolute(DIR)


# ---------------------------------------------------------------------------------------------
# SaveManager
# ---------------------------------------------------------------------------------------------

func _test_save_basics() -> void:
	var sm := _new_save("save.json")
	_rm(sm.save_path)
	sm.load_save()
	_eq(sm.last_load_status, &"missing", "fresh save status")
	_eq(sm.total_stars(), 0, "fresh total stars")
	_eq(sm.stars_for(&"med_1"), 0, "fresh stars_for")
	_check(sm.is_level_unlocked(&"med_1"), "med_1 unlocked at start")
	_check(not sm.is_level_unlocked(&"med_2"), "med_2 locked at start")
	_check(not sm.is_level_unlocked(&"arctic_1"), "arctic_1 locked at start")
	_check(sm.is_destination_unlocked(&"med"), "med destination open")
	_check(not sm.is_destination_unlocked(&"arctic"), "arctic destination locked")
	_check(not sm.is_destination_unlocked(&"underworld"), "underworld destination locked")
	_eq(sm.stars_required(&"arctic"), 10, "arctic stars_required default")
	_eq(sm.stars_required(&"underworld"), 24, "underworld stars_required default")
	_eq(sm.highest_cleared_index(), 0, "nothing cleared")
	_check(sm.tier_unlocked(1), "tier I always")
	_check(not sm.tier_unlocked(2) and not sm.tier_unlocked(3), "tiers II/III locked")
	_check(sm.level_lock_reason(&"med_2") != "", "lock reason for med_2")
	_check(sm.level_lock_reason(&"arctic_1") != "", "lock reason for arctic_1")
	_eq(sm.level_lock_reason(&"med_1"), "", "no lock reason for med_1")
	_eq(sm.next_level_id(&"med_6"), &"arctic_1", "next level crosses destinations")
	_eq(sm.next_level_id(&"underworld_6"), &"", "no level after the last")
	_eq(sm.best_for(&"med_1")["played"], false, "best_for unplayed")
	sm.free()


func _test_save_progression() -> void:
	var sm := _new_save("save.json")
	_rm(sm.save_path)
	sm.load_save()
	var emitted: Array[int] = [0]
	sm.progress_changed.connect(func() -> void: emitted[0] += 1)

	var r: Dictionary = sm.record_result({"level_id": &"med_1", "stars": 2, "rating": 60.5, "profit": 300})
	_eq(r["new_stars"], 2, "new_stars first clear")
	_eq(r["total_stars"], 2, "total_stars in result")
	_eq(_sorted_strings(r["newly_unlocked_levels"]), ["med_2"], "med_1 unlocks med_2 only")
	_eq(_sorted_strings(r["newly_unlocked_rooms"]), ["cinema"], "level 2 reachable -> cinema")
	_eq(r["newly_unlocked_destinations"].size(), 0, "no destination yet")
	_eq(r["newly_unlocked_features"].size(), 0, "no feature yet")
	_eq(emitted[0], 1, "progress_changed emitted")
	_eq(sm.stars_for(&"med_1"), 2, "stars stored")
	_check(sm.is_level_unlocked(&"med_2"), "med_2 unlocked after med_1")

	# Worse replay never lowers bests; better rating / profit raise them independently.
	var r2: Dictionary = sm.record_result({"level_id": &"med_1", "stars": 1, "rating": 70.0, "profit": 100})
	_eq(r2["new_stars"], 0, "no new stars on a worse replay")
	var best: Dictionary = sm.best_for(&"med_1")
	_eq(best["stars"], 2, "best stars kept")
	_check(is_equal_approx(best["best_rating"], 70.0), "best rating raised")
	_eq(best["best_profit"], 300, "best profit kept")
	_eq(best["plays"], 2, "plays counted")
	_eq(r2["newly_unlocked_levels"].size(), 0, "replay unlocks nothing")

	# A 0-star run (mutiny) does not unlock the next level.
	var r3: Dictionary = sm.record_result({"level_id": &"med_2", "stars": 0, "rating": 10.0, "profit": -50})
	_eq(r3["new_stars"], 0, "0 stars")
	_check(not sm.is_level_unlocked(&"med_3"), "med_3 still locked after 0-star med_2")
	_eq(sm.best_for(&"med_2")["best_profit"], -50, "negative profit recorded for first play")

	var r4: Dictionary = sm.record_result({"level_id": &"med_2", "stars": 1, "rating": 40.0, "profit": 20})
	_eq(_sorted_strings(r4["newly_unlocked_levels"]), ["med_3"], "med_2 (1 star) unlocks med_3")
	_eq(_sorted_strings(r4["newly_unlocked_rooms"]), ["generator", "gym", "medbay", "water_tank"], "level 3 rooms")

	var r5: Dictionary = sm.record_result({"level_id": &"med_3", "stars": 3, "rating": 90.0, "profit": 900})
	_eq(_sorted_strings(r5["newly_unlocked_features"]), ["tier_2"], "tier II after clearing level 3")
	_check(sm.tier_unlocked(2) and not sm.tier_unlocked(3), "tier II open, tier III closed")
	_eq(_sorted_strings(r5["newly_unlocked_rooms"]), ["arcade", "sauna"], "level 4 rooms")
	_eq(sm.highest_cleared_index(), 3, "highest cleared index")
	_eq(sm.total_stars(), 6, "total stars 2+1+3")

	# Destination unlock by total stars: 10 -> Arctic.
	sm.record_result({"level_id": &"med_4", "stars": 3, "rating": 80.0, "profit": 500})
	_eq(sm.total_stars(), 9, "total stars 9")
	_check(not sm.is_destination_unlocked(&"arctic"), "arctic needs 10")
	_check(not sm.is_level_unlocked(&"arctic_1"), "arctic_1 closed at 9 stars")
	var r6: Dictionary = sm.record_result({"level_id": &"med_5", "stars": 1, "rating": 55.0, "profit": 100})
	_eq(sm.total_stars(), 10, "total stars 10")
	_check(sm.is_destination_unlocked(&"arctic"), "arctic open at 10")
	_eq(_sorted_strings(r6["newly_unlocked_destinations"]), ["arctic"], "arctic newly unlocked")
	_eq(_sorted_strings(r6["newly_unlocked_levels"]), ["arctic_1", "med_6"], "med_6 and arctic_1 unlock")
	_check(sm.is_level_unlocked(&"arctic_1"), "arctic_1 open")
	_check(not sm.is_level_unlocked(&"arctic_2"), "arctic_2 needs arctic_1")
	_check("ice_rink" in _sorted_strings(r6["newly_unlocked_rooms"]) and "elevator" in _sorted_strings(r6["newly_unlocked_rooms"]),
		"level 7 reachable -> ice_rink + elevator")

	# Tier III after campaign level 9 (arctic_3).
	sm.record_result({"level_id": &"arctic_1", "stars": 1, "rating": 50.0, "profit": 1})
	sm.record_result({"level_id": &"arctic_2", "stars": 1, "rating": 50.0, "profit": 1})
	_check(not sm.tier_unlocked(3), "tier III not yet")
	var r7: Dictionary = sm.record_result({"level_id": &"arctic_3", "stars": 1, "rating": 50.0, "profit": 1})
	_eq(_sorted_strings(r7["newly_unlocked_features"]), ["tier_3"], "tier III after level 9")
	_check(sm.tier_unlocked(3), "tier III open")
	_eq(sm.highest_cleared_index(), 9, "highest cleared 9")
	_eq(sm.feature_display_name(&"tier_2"), "Tier II upgrades", "feature name")

	# Underworld at 24 stars (currently 13: med 2+1+3+3+1, arctic 1+1+1).
	_check(not sm.is_destination_unlocked(&"underworld"), "underworld closed")
	sm.record_result({"level_id": &"med_6", "stars": 3, "rating": 90.0, "profit": 1})
	sm.record_result({"level_id": &"arctic_1", "stars": 3, "rating": 90.0, "profit": 1})
	sm.record_result({"level_id": &"arctic_2", "stars": 3, "rating": 90.0, "profit": 1})
	sm.record_result({"level_id": &"arctic_3", "stars": 3, "rating": 90.0, "profit": 1})
	_eq(sm.total_stars(), 22, "22 stars")
	_check(not sm.is_destination_unlocked(&"underworld"), "underworld still closed at 22")
	var r8: Dictionary = sm.record_result({"level_id": &"arctic_4", "stars": 3, "rating": 90.0, "profit": 1})
	_eq(sm.total_stars(), 25, "25 stars")
	_check(sm.is_destination_unlocked(&"underworld"), "underworld open")
	_eq(_sorted_strings(r8["newly_unlocked_destinations"]), ["underworld"], "underworld newly unlocked")
	_check(&"underworld_1" in r8["newly_unlocked_levels"], "underworld_1 newly unlocked")
	_check(&"casino" in r8["newly_unlocked_rooms"], "casino newly reachable")
	_check(sm.is_level_unlocked(&"underworld_1"), "underworld_1 open")
	_check(not sm.is_level_unlocked(&"underworld_2"), "underworld_2 needs underworld_1")

	sm.reset_progress()
	_eq(sm.total_stars(), 0, "reset_progress clears stars")
	_check(not sm.is_level_unlocked(&"med_2"), "reset re-locks levels")
	sm.free()


func _test_save_persistence() -> void:
	var path_name: String = "rt.json"
	var a := _new_save(path_name)
	_rm(a.save_path)
	a.load_save()
	a.record_result({"level_id": &"med_1", "stars": 3, "rating": 88.5, "profit": 1234})
	a.record_result({"level_id": &"med_2", "stars": 1, "rating": 41.0, "profit": -5})
	_check(FileAccess.file_exists(a.save_path), "save file written")
	_check(not FileAccess.file_exists(a.save_path + ".tmp"), "no tmp file left behind")
	var text: String = FileAccess.get_file_as_string(a.save_path)
	var parsed: Variant = JSON.parse_string(text)
	_check(parsed is Dictionary, "save is JSON object")
	if parsed is Dictionary:
		_eq(int(parsed.get("version", 0)), 1, "save version")
		_check((parsed["levels"] as Dictionary).has("med_1"), "levels contains med_1")
		_eq(int(parsed["levels"]["med_1"]["stars"]), 3, "json stars")

	var b := _new_save(path_name)
	_check(b.load_save(), "reload ok")
	_eq(b.last_load_status, &"ok", "reload status")
	_eq(b.stars_for(&"med_1"), 3, "stars survive reload")
	_eq(b.total_stars(), 4, "total survives reload")
	var bf: Dictionary = b.best_for(&"med_1")
	_check(is_equal_approx(bf["best_rating"], 88.5), "best rating survives reload")
	_eq(bf["best_profit"], 1234, "best profit survives reload")
	_eq(b.best_for(&"med_2")["best_profit"], -5, "negative profit survives reload")
	_check(b.is_level_unlocked(&"med_3"), "unlocks derived from loaded data")
	a.free()
	b.free()

	# Unknown top-level keys are preserved across a rewrite.
	var f := FileAccess.open("%s/s2.json" % DIR, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "levels": {}, "settings": {"x": 1}, "future": [1, 2]}))
	f.close()
	var c := _new_save("s2.json")
	c.load_save()
	c.record_result({"level_id": &"med_1", "stars": 1, "rating": 10.0, "profit": 1})
	var parsed2: Variant = JSON.parse_string(FileAccess.get_file_as_string(c.save_path))
	_check(parsed2 is Dictionary and parsed2.has("future") and parsed2.has("settings"), "unknown keys preserved")
	c.free()


func _test_save_corrupt() -> void:
	var path: String = "%s/save.json" % DIR
	for payload: String in ["{this is not json", "[1, 2, 3]", "", "<<<<<<< HEAD merge conflict garbage"]:
		_rm(path)
		_rm(path + ".corrupt")
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(payload)
		f.close()
		var sm := _new_save("save.json")
		var ok: bool = sm.load_save()
		_check(not ok, "corrupt load reports false for %s" % payload.left(12))
		_eq(sm.last_load_status, &"corrupt", "corrupt status")
		_check(FileAccess.file_exists(path + ".corrupt"), "corrupt file backed up")
		_check(not FileAccess.file_exists(path), "corrupt file moved away")
		_eq(sm.total_stars(), 0, "fresh state after corruption")
		sm.record_result({"level_id": &"med_1", "stars": 1, "rating": 50.0, "profit": 10})
		var again := _new_save("save.json")
		_check(again.load_save() and again.stars_for(&"med_1") == 1, "new save valid after recovery")
		again.free()
		sm.free()
	# Garbage level entries are tolerated.
	_rm(path)
	var g := FileAccess.open(path, FileAccess.WRITE)
	g.store_string(JSON.stringify({"version": 1, "levels": {"med_1": "oops", "med_2": {"stars": 99, "best_rating": "x"}, "med_3": {"stars": -4}}}))
	g.close()
	var tolerant := _new_save("save.json")
	_check(tolerant.load_save(), "garbage entries tolerated")
	_eq(tolerant.stars_for(&"med_1"), 0, "non-dict entry ignored")
	_eq(tolerant.stars_for(&"med_2"), 3, "stars clamped to 3")
	_eq(tolerant.stars_for(&"med_3"), 0, "negative stars clamped")
	tolerant.free()


func _test_save_unlock_all() -> void:
	var sm := _new_save("save.json")
	_rm(sm.save_path)
	sm.load_save()
	sm.unlock_all = true
	_check(sm.is_level_unlocked(&"underworld_6"), "unlock_all: last level")
	_check(sm.is_destination_unlocked(&"underworld"), "unlock_all: destination")
	_check(sm.tier_unlocked(3), "unlock_all: tier III")
	_eq(sm.highest_cleared_index(), 18, "unlock_all: highest cleared")
	_check(&"casino" in sm.unlocked_rooms(), "unlock_all: casino unlocked")
	_eq(sm.total_stars(), 0, "unlock_all does not fake stars")
	var r: Dictionary = sm.record_result({"level_id": &"med_1", "stars": 1, "rating": 50.0, "profit": 5})
	_check(&"med_2" in r["newly_unlocked_levels"], "newly unlocked computed against real state under unlock_all")
	sm.free()


func _test_save_content_provider() -> void:
	var sm := _new_save("save.json")
	_rm(sm.save_path)
	sm.load_save()
	sm.content = FakeDB.new()
	_eq(sm.stars_required(&"arctic"), 3, "stars_required read from content")
	_check(not sm.is_destination_unlocked(&"arctic"), "fake arctic closed")
	_check(sm.is_level_unlocked(&"med_1"), "fake med_1 open")
	var r: Dictionary = sm.record_result({"level_id": "med_1", "stars": 3, "rating": 90.0, "profit": 1})
	_check(sm.is_destination_unlocked(&"arctic"), "fake arctic open at 3 stars")
	_eq(_sorted_strings(r["newly_unlocked_destinations"]), ["arctic"], "fake arctic newly unlocked")
	_check(&"med_2" in r["newly_unlocked_levels"] and &"arctic_1" in r["newly_unlocked_levels"], "fake levels unlocked")
	_eq(_sorted_strings(r["newly_unlocked_rooms"]), ["igloo", "laser"], "fake rooms from content")
	_eq(sm.unlocked_rooms_at(1).size(), 1, "rooms at index 1 from content")
	_eq(sm.unlocked_rooms_at(4).size(), 3, "rooms at index 4 from content")
	_check(sm.level_lock_reason(&"arctic_2") != "", "lock reason with content")
	_check(sm.level_lock_reason(&"underworld_1").contains("Fake Underworld"), "lock reason uses destination display name")
	sm.free()


## Integration with the real ContentDB autoload (skipped when it has no campaign data yet).
func _test_save_with_real_content() -> void:
	var db: Node = root.get_node_or_null("ContentDB")
	if db == null or not db.has_method("campaign") or db.campaign().size() != 18:
		print("note: real ContentDB not available, skipping integration test")
		return
	var sm: Node = SaveScript.new()
	sm.save_path = "%s/save.json" % DIR
	_rm(sm.save_path)
	sm.load_save()
	_eq(sm.stars_required(&"arctic"), 10, "real content: arctic stars")
	_eq(sm.stars_required(&"underworld"), 24, "real content: underworld stars")
	_eq(sm.unlocked_rooms_at(1).size(), 7, "real content: 7 rooms at level 1")
	_check(&"casino" not in sm.unlocked_rooms_at(12) and &"casino" in sm.unlocked_rooms_at(13), "real content: casino at 13")
	_check(&"elevator" in sm.unlocked_rooms_at(7) and &"elevator" not in sm.unlocked_rooms_at(6), "real content: elevator at 7")
	var last: Dictionary = {}
	for i in range(1, 5):
		last = sm.record_result({"level_id": "med_%d" % i, "stars": 3, "rating": 90.0, "profit": 100})
	_eq(sm.total_stars(), 12, "real content: 12 stars")
	_check(&"arctic" in last["newly_unlocked_destinations"], "real content: arctic unlocked by med_4")
	_check(sm.is_level_unlocked(&"arctic_1") and not sm.is_level_unlocked(&"arctic_2"), "real content: sequential in arctic")
	_check(sm.tier_unlocked(2) and not sm.tier_unlocked(3), "real content: tier II only")
	sm.free()


# ---------------------------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------------------------

func _new_settings(node_name: String = "TestSettings") -> Node:
	var s: Node = SettingsScript.new()
	s.name = node_name
	s.settings_path = "%s/settings.json" % DIR
	return s


func _key_event(code: Key, physical: bool = true) -> InputEventKey:
	var e := InputEventKey.new()
	e.pressed = true
	if physical:
		e.physical_keycode = code
		e.keycode = code
	else:
		e.keycode = code
		e.physical_keycode = code
	return e


func _test_settings() -> void:  # coroutine: nodes need a frame to run _ready
	_rm("%s/settings.json" % DIR)
	var s := _new_settings()
	root.add_child(s)
	await process_frame  # _ready -> setup()

	# Actions exist with their defaults.
	for action in SettingsScript.ACTIONS:
		_check(InputMap.has_action(action), "action registered: %s" % action)
	_eq(s.get_bindings(&"pause").size(), 2, "pause has two default bindings")
	_check(InputMap.event_is_action(_key_event(KEY_SPACE), &"pause"), "Space -> pause")
	_check(InputMap.event_is_action(_key_event(KEY_P), &"pause"), "P -> pause")
	_check(InputMap.event_is_action(_key_event(KEY_1), &"speed_1"), "1 -> speed_1")
	_check(InputMap.event_is_action(_key_event(KEY_3), &"speed_3"), "3 -> speed_3")
	_check(InputMap.event_is_action(_key_event(KEY_EQUAL, false), &"zoom_in"), "= -> zoom_in")
	_check(InputMap.event_is_action(_key_event(KEY_KP_ADD, false), &"zoom_in"), "numpad + -> zoom_in")
	_check(InputMap.event_is_action(_key_event(KEY_MINUS, false), &"zoom_out"), "- -> zoom_out")
	_check(InputMap.event_is_action(_key_event(KEY_A), &"pan_left"), "A -> pan_left")
	_check(InputMap.event_is_action(_key_event(KEY_RIGHT), &"pan_right"), "Right -> pan_right")
	_check(InputMap.event_is_action(_key_event(KEY_W), &"pan_up"), "W -> pan_up")
	_check(InputMap.event_is_action(_key_event(KEY_DOWN), &"pan_down"), "Down -> pan_down")
	_check(InputMap.event_is_action(_key_event(KEY_ESCAPE), &"cancel"), "Esc -> cancel")
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	_check(InputMap.event_is_action(rmb, &"cancel"), "right click -> cancel")
	_check(InputMap.event_is_action(_key_event(KEY_F11), &"toggle_fullscreen"), "F11 -> toggle_fullscreen")

	# Values: defaults, clamping, change signal (only on real change).
	_check(is_equal_approx(s.master_volume, 0.8) and is_equal_approx(s.music_volume, 0.7) and is_equal_approx(s.sfx_volume, 0.9), "default volumes")
	_check(not s.colorblind and not s.fullscreen and s.screen_shake and s.show_tutorial_hints, "default toggles")
	var keys: Array[StringName] = []
	s.changed.connect(func(k: StringName) -> void: keys.append(k))
	s.master_volume = 0.5
	s.master_volume = 0.5
	_eq(keys, [&"master_volume"], "changed emitted once per real change")
	s.music_volume = 3.0
	_check(is_equal_approx(s.music_volume, 1.0), "volume clamped to 1")
	s.sfx_volume = -1.0
	_check(is_equal_approx(s.sfx_volume, 0.0), "volume clamped to 0")
	s.colorblind = true
	s.screen_shake = false
	s.show_tutorial_hints = false
	_check(&"colorblind" in keys and &"screen_shake" in keys and &"show_tutorial_hints" in keys, "bool changes emit")
	_check(s.set_value(&"sfx_volume", 0.25) and is_equal_approx(s.get_value(&"sfx_volume"), 0.25), "generic set/get")
	_check(not s.set_value(&"nonsense", 1), "unknown key rejected")

	# Rebinding.
	var f_key := _key_event(KEY_F)
	_check(s.rebind(&"pause", f_key, 0), "rebind pause -> F")
	_check(InputMap.event_is_action(_key_event(KEY_F), &"pause"), "F now pauses")
	_check(not InputMap.event_is_action(_key_event(KEY_SPACE), &"pause"), "Space no longer pauses")
	_check(InputMap.event_is_action(_key_event(KEY_P), &"pause"), "alternate P still pauses")
	_eq(s.get_bindings(&"pause").size(), 2, "still two bindings")
	_eq(s.event_display_text(s.get_bindings(&"pause")[0]), "F", "display text of rebound key")
	_check(s.find_conflicts(_key_event(KEY_F), &"speed_1").has(&"pause"), "conflict detected")
	_check(not s.find_conflicts(_key_event(KEY_F), &"pause").has(&"pause"), "no self-conflict")
	# Binding the primary key into the other slot swaps rather than duplicating.
	_check(s.rebind(&"pause", _key_event(KEY_P), 0), "rebind slot 0 to the key held by slot 1")
	_eq(s.get_bindings(&"pause").size(), 1, "duplicate binding collapsed")
	_check(s.rebind(&"pause", _key_event(KEY_SPACE), 1), "rebind slot 1")
	_eq(s.get_bindings(&"pause").size(), 2, "back to two bindings")
	_check(not s.rebind(&"nonsense", f_key, 0), "unknown action rejected")
	_check(not s.rebind(&"pause", InputEventMouseMotion.new(), 0), "unsupported event rejected")
	_check(not s.rebind(&"pause", f_key, 7), "bad slot rejected")
	var mid := InputEventMouseButton.new()
	mid.button_index = MOUSE_BUTTON_MIDDLE
	_check(s.rebind(&"cancel", mid, 1), "mouse button rebind")
	_eq(s.event_display_text(mid), "Middle Click", "mouse display text")
	_eq(s.event_display_text(_key_event(KEY_ESCAPE)), "Esc", "Esc display text")
	_eq(s.event_display_text(_key_event(KEY_SPACE)), "Space", "Space display text")
	_eq(s.event_display_text(_key_event(KEY_KP_ADD, false)), "Num +", "numpad + display text")
	_check(s.action_display_name(&"pause") != "" and s.action_display_name(&"zoom_in") != "zoom_in", "action display names")
	_check(s.clear_binding(&"pan_up", 1), "clear_binding")
	_eq(s.get_bindings(&"pan_up").size(), 1, "binding cleared")

	# Persistence: a second instance (same path) sees values and remaps.
	_check(s.save_now(), "save_now ok")
	_check(FileAccess.file_exists(s.settings_path), "settings file exists")
	_check(not FileAccess.file_exists(s.settings_path + ".tmp"), "no settings tmp left")
	root.remove_child(s)
	var s2 := _new_settings("TestSettingsB")
	root.add_child(s2)
	await process_frame
	_check(is_equal_approx(s2.master_volume, 0.5), "master volume persisted")
	_check(is_equal_approx(s2.music_volume, 1.0), "music volume persisted")
	_check(is_equal_approx(s2.sfx_volume, 0.25), "sfx volume persisted")
	_check(s2.colorblind and not s2.screen_shake and not s2.show_tutorial_hints, "toggles persisted")
	_check(InputMap.event_is_action(_key_event(KEY_P), &"pause") and InputMap.event_is_action(_key_event(KEY_SPACE), &"pause"), "pause remap persisted")
	_eq(s2.get_bindings(&"pan_up").size(), 1, "cleared binding persisted")
	_check(InputMap.event_is_action(mid, &"cancel"), "mouse remap persisted")
	s2.reset_bindings()
	_check(InputMap.event_is_action(_key_event(KEY_F11), &"toggle_fullscreen") and s2.get_bindings(&"pan_up").size() == 2, "reset_bindings restores defaults")
	_check(not InputMap.event_is_action(mid, &"cancel"), "reset removed the mouse remap")
	s2.reset_values()
	_check(is_equal_approx(s2.master_volume, 0.8) and s2.screen_shake and not s2.colorblind, "reset_values")
	root.remove_child(s2)
	s.free()
	s2.free()

	# A garbage config file must not crash and must leave defaults.
	var bad_path: String = "%s/bad.json" % DIR
	var bf := FileAccess.open(bad_path, FileAccess.WRITE)
	bf.store_string("{\"values\": {\"master_volume\": ")
	bf.close()
	var s3 := _new_settings("TestSettingsC")
	s3.settings_path = bad_path
	root.add_child(s3)
	await process_frame
	_check(is_equal_approx(s3.master_volume, 0.8), "garbage config -> defaults")
	root.remove_child(s3)
	s3.free()


# ---------------------------------------------------------------------------------------------
# Synthesis
# ---------------------------------------------------------------------------------------------

func _test_synth_helpers() -> void:
	_eq(SU.note_midi("C4"), 60, "C4")
	_eq(SU.note_midi("A4"), 69, "A4")
	_eq(SU.note_midi("F#3"), 54, "F#3")
	_eq(SU.note_midi("Bb5"), 82, "Bb5")
	_eq(SU.note_midi("r"), -1, "rest")
	_eq(SU.note_midi("H4"), -1, "bad letter")
	_check(is_equal_approx(SU.hz(69), 440.0) and is_equal_approx(SU.hz(81), 880.0), "midi to hz")
	var b := SU.buf(100)
	for i in 100:
		b[i] = 0.5 + 0.25 * sin(i * 0.3)
	SU.remove_dc(b)
	_check(absf(SU.mean(b)) < 1e-6, "remove_dc")
	SU.normalize(b, -6.0)
	_check(absf(SU.to_db(SU.peak(b)) - (-6.0)) < 0.01, "normalize to -6 dB")
	var loud := SU.buf(1000)
	for i in 1000:
		loud[i] = 3.0 * sin(i * 0.05)
	SU.soft_limit(loud, -1.5, -9.0)
	_check(SU.to_db(SU.peak(loud)) < -1.49, "soft limiter stays under the ceiling")
	var a := SU.buf(10)
	var src := SU.buf(6)
	for i in 6:
		src[i] = 1.0
	SU.mix_wrap(a, src, 7, 1.0)
	_check(a[7] == 1.0 and a[9] == 1.0 and a[0] == 1.0 and a[2] == 1.0 and a[3] == 0.0, "mix_wrap wraps around the end")
	var pcm := SU.to_pcm16(PackedFloat32Array([0.0, 1.0, -1.0, 2.0]))
	_eq(pcm.decode_s16(2), 32767, "pcm16 full scale")
	_eq(pcm.decode_s16(4), -32767, "pcm16 negative")
	_eq(pcm.decode_s16(6), 32767, "pcm16 clamps")
	var stream: AudioStreamWAV = SU.make_stream(pcm, 22050, 4)
	_check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end == 4, "looped stream flags")


func _test_music_data() -> void:
	var all_bars: Array[String] = []
	all_bars.append_array(MusicBank.PORT_MELODY)
	all_bars.append_array(MusicBank.VOY_MELODY_A)
	all_bars.append_array(MusicBank.VOY_MELODY_B)
	all_bars.append_array(MusicBank.VOY_MELODY_A2)
	for i in all_bars.size():
		_check(is_equal_approx(MusicBank.bar_beats(all_bars[i]), 4.0), "melody bar %d has 4 beats: %s" % [i, all_bars[i]])
		for e: Array in MusicBank.parse_bar(all_bars[i]):
			_check(int(e[1]) >= 59 or int(e[1]) == -1 and e[2] > 0.0, "melody note in range: %s" % all_bars[i])
	_eq(MusicBank.PORT_CHORDS.size(), MusicBank.PORT_MELODY.size(), "port: one chord per melody bar")
	_eq(MusicBank.PORT_UKE.size(), MusicBank.PORT_CHORDS.size(), "port: one uke pattern per bar")
	_eq(MusicBank.VOY_CHORDS_A.size(), MusicBank.VOY_MELODY_A.size(), "voyage A: chords per bar")
	_eq(MusicBank.VOY_CHORDS_B.size(), MusicBank.VOY_MELODY_B.size(), "voyage B: chords per bar")
	for c in MusicBank.PORT_CHORDS + MusicBank.VOY_CHORDS_A + MusicBank.VOY_CHORDS_B:
		_check(MusicBank.CHORDS.has(c), "known chord %s" % c)
	for p in MusicBank.PORT_UKE:
		_check(MusicBank.UKE_PATTERNS.has(p), "known uke pattern %s" % p)


func _test_sfx_synthesis() -> void:
	for sfx_name in SfxBank.NAMES:
		var b: PackedFloat32Array = SfxBank.render(sfx_name)
		_check(b.size() > 100, "%s rendered" % sfx_name)
		if b.is_empty():
			continue
		_check(SU.to_db(SU.peak(b)) <= -1.0, "%s peak <= -1 dBFS (%.2f)" % [sfx_name, SU.to_db(SU.peak(b))])
		_check(absf(SU.mean(b)) < 0.002, "%s no DC offset" % sfx_name)
		_check(absf(b[0]) < 0.01 and absf(b[b.size() - 1]) < 0.01, "%s starts/ends silent (no click)" % sfx_name)
		_check(SU.rms(b) > 0.003, "%s is audible" % sfx_name)
	# Rendering is deterministic.
	var x: PackedFloat32Array = SfxBank.render(&"mess_splat")
	var y: PackedFloat32Array = SfxBank.render(&"mess_splat")
	_check(x == y, "synthesis is deterministic")
	_eq(SfxBank.render(&"not_a_sound").size(), 0, "unknown sound renders nothing")
	# The one-shot results jingle (music loops are checked by render_sfx.gd).
	var d: Dictionary = MusicBank.render(&"results")
	var jingle: PackedFloat32Array = d["main"]
	_check(not jingle.is_empty() and not bool(d["loop"]), "results jingle rendered, not looped")
	_check(SU.to_db(SU.peak(jingle)) <= -1.0, "results jingle peak")
	_check(absf(jingle[0]) < 0.01 and absf(jingle[jingle.size() - 1]) < 0.01, "results jingle starts/ends silent")
	_check(MusicBank.render(&"nope").is_empty(), "unknown track")
	var cancelled: Dictionary = MusicBank.render(&"port", func() -> bool: return true)
	_check(cancelled.is_empty(), "cancel callable aborts a render")


# ---------------------------------------------------------------------------------------------
# AudioManager (no synthesis threads under --headless; streams are injected)
# ---------------------------------------------------------------------------------------------

func _dummy_stream() -> AudioStreamWAV:
	var b := SU.buf(2000)
	for i in b.size():
		b[i] = 0.2 * sin(i * 0.2)
	return SU.make_stream(SU.to_pcm16(b), 22050)


func _test_audio_manager() -> void:  # coroutine
	_rm("%s/settings.json" % DIR)
	var s := _new_settings("TestSettingsAudio")
	root.add_child(s)
	var am: Node = AudioScript.new()
	am.name = "TestAudioManager"
	am.settings_node = s
	root.add_child(am)
	await process_frame

	_check(AudioServer.get_bus_index(&"Music") != -1 and AudioServer.get_bus_index(&"SFX") != -1, "Music / SFX buses created")
	var sfx_bus: int = AudioServer.get_bus_index(&"SFX")
	_eq(AudioServer.get_bus_send(sfx_bus), &"Master", "SFX bus sends to Master")
	_check(not am.is_ready(), "nothing synthesised in headless by default")

	# Volumes follow Settings live.
	s.master_volume = 0.5
	_check(absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.5)) < 0.01, "master bus follows Settings")
	s.sfx_volume = 0.25
	_check(absf(AudioServer.get_bus_volume_db(sfx_bus) - linear_to_db(0.25)) < 0.01, "sfx bus follows Settings")
	s.music_volume = 0.0
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Music")), "music bus mutes at 0")
	s.music_volume = 0.7
	_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Music")), "music bus unmutes")

	# Unknown / unrendered sounds are ignored, known ones play and are rate limited.
	am.play_sfx(&"coin")
	_check(not am._last_play.has(&"coin"), "unrendered sound ignored")
	var ds := _dummy_stream()
	for sfx_name in SfxBank.NAMES:
		am._sfx[sfx_name] = ds
	am.play_sfx(&"coin")
	_check(am._last_play.has(&"coin"), "rendered sound plays")
	for i in 30:
		am.play_sfx(&"coin")
	_eq(am._stack_times[&"coin"].size(), 3, "coin burst limited to 3 stacked variants")
	var playing: int = 0
	for p: AudioStreamPlayer in am._pool:
		if p.playing:
			playing += 1
	_check(playing <= 4, "a coin storm uses at most 4 voices (%d)" % playing)
	am.play_sfx(&"ui_hover")
	am.play_sfx(&"ui_hover")
	_check(am._last_play.has(&"ui_hover"), "ui_hover played once, repeats dropped")
	am.play_sfx(&"not_a_sound")

	# Music requests before the track exists are remembered; no crash on stop.
	am.play_music(&"port")
	_eq(am._requested_music, &"port", "pending music request kept")
	am.stop_music()
	_eq(am._requested_music, &"", "stop clears the request")
	am._music[&"port"] = {"main": SU.make_stream(SU.to_pcm16(SU.buf(22050)), 22050, 22050), "perc": null, "loop": true}
	am._music[&"voyage"] = {
		"main": SU.make_stream(SU.to_pcm16(SU.buf(22050)), 22050, 22050),
		"perc": SU.make_stream(SU.to_pcm16(SU.buf(22050)), 22050, 22050), "loop": true}
	am.play_music(&"port")
	_eq(am.current_music(), &"port", "port music started")
	am.play_music(&"voyage")
	_eq(am.current_music(), &"voyage", "voyage music crossfades in")
	am.set_music_intensity(0.7)
	am.play_music(&"voyage")
	_eq(am.current_music(), &"voyage", "re-requesting the current track is a no-op")
	am.stop_music()
	_eq(am.current_music(), &"", "stopped")

	# bind_sim maps signals to sounds.
	var sim := FakeSim.new()
	am.bind_sim(sim)
	am._last_play.clear()
	sim.room_used.emit(1, 2, 0)
	_check(not am._last_play.has(&"coin"), "room_used with spend 0 is silent")
	sim.room_used.emit(1, 2, 7)
	_check(am._last_play.has(&"coin"), "room_used with spend > 0 -> coin")
	sim.mess_spawned.emit(1)
	sim.mess_cleaned.emit(1)
	sim.room_broken.emit(3)
	sim.room_repaired.emit(3)
	sim.guest_slipped.emit(4)
	sim.guest_got_sick.emit(4)
	sim.guest_cured.emit(4)
	sim.ghost_spawned.emit(5)
	sim.ghost_banished.emit(5)
	sim.event_started.emit(&"lunch_rush")
	sim.wave_started.emit(0, 5)
	sim.guest_stormed_off.emit(9)
	sim.money_changed.emit(100, -90, &"hires")
	sim.mutiny_warning.emit(20.0)
	sim.mutiny_cleared.emit()
	for expected in [&"mess_splat", &"clean", &"breakdown", &"repair_done", &"slip", &"sick", &"cure", &"ghost",
			&"banish", &"event_horn", &"wave_board", &"error_buzz", &"hire", &"mutiny_warn"]:
		_check(am._last_play.has(expected), "sim signal -> %s" % expected)
	am._last_play.clear()
	sim.mutiny_warning.emit(19.0)
	_check(not am._last_play.has(&"mutiny_warn"), "mutiny warning is throttled")
	sim.guest_boarded.emit(1)
	sim.guest_patience_out.emit(1, 2)
	sim.event_ended.emit(&"x")
	_check(am._last_play.is_empty(), "boarding / patience / event end are silent")
	sim.voyage_ended.emit({"stars": 2, "mutiny": false})
	_eq(am._requested_music, &"results", "voyage_ended requests the results jingle (not rendered here)")
	am.unbind_sim()
	am._last_play.clear()
	sim.room_broken.emit(1)
	_check(am._last_play.is_empty(), "unbind_sim disconnects")
	# Rebinding to a different sim replaces the old binding.
	var sim2 := FakeSim.new()
	am.bind_sim(sim)
	am.bind_sim(sim2)
	sim.room_broken.emit(1)
	_check(am._last_play.is_empty(), "old sim disconnected after rebinding")
	sim2.room_broken.emit(1)
	_check(am._last_play.has(&"breakdown"), "new sim connected")

	# A sim with unexpected signal arities is still tolerated.
	var odd := OddSim.new()
	am.bind_sim(odd)
	am._last_play.clear()
	odd.room_used.emit(1)
	odd.mess_spawned.emit()
	_check(am._last_play.has(&"coin") and am._last_play.has(&"mess_splat"), "arity-mismatched sim handled")

	# Buttons get click / hover sounds automatically.
	var btn := Button.new()
	root.add_child(btn)
	await process_frame
	am._last_play.clear()
	btn.pressed.emit()
	_check(am._last_play.has(&"ui_click"), "button press -> ui_click")
	var quiet := Button.new()
	quiet.set_meta(&"no_ui_sound", true)
	root.add_child(quiet)
	await process_frame
	am._last_play.clear()
	quiet.pressed.emit()
	_check(not am._last_play.has(&"ui_click"), "no_ui_sound meta opts out")
	btn.free()
	quiet.free()

	am.unbind_sim()
	am.stop_music(0.01)
	for p: AudioStreamPlayer in am._pool:
		p.stop()
	for slot in am._slots:
		slot.main.stop()
		slot.perc.stop()
	root.remove_child(am)
	root.remove_child(s)
	am.free()
	s.free()


class OddSim:
	extends RefCounted
	signal room_used(room_uid: int)
	signal mess_spawned()
