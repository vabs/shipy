extends Node
## AudioManager autoload ("AudioManager") — see docs/SPEC.md §8.
##
## * Creates the Music / SFX buses (and a safety limiter on Master) if they are missing and keeps
##   all three bus volumes in sync with `Settings` (live, via Settings.changed).
## * Synthesises every sound procedurally at startup on two worker threads (SFX first, then the
##   music loops) so boot is never blocked; sounds that are not ready yet are silently skipped and a
##   pending `play_music()` request starts as soon as its loop has been rendered.
##   Under `--headless` nothing is synthesised unless the user arg `--audio-synth` is given.
## * `play_sfx()` uses a pool of AudioStreamPlayers and rate-limits identical sounds.
## * Music: "port", "voyage" (seamless loops, voyage has an extra percussion layer controlled by
##   `set_music_intensity()`), "results" (one-shot jingle). Crossfades over 0.8 s.
## * `bind_sim(sim)` maps SimWorld signals to sounds; every BaseButton that enters the tree gets
##   click / hover sounds automatically (set meta "no_ui_sound" on a button to opt out).

signal sfx_ready(name: StringName)
signal music_ready(name: StringName)
## Both synthesis threads are done.
signal synth_finished
## A non-looping track (the results jingle) reached its end.
signal music_finished(name: StringName)

const SU := preload("res://src/audio/synth_util.gd")
const SfxBank := preload("res://src/audio/sfx_bank.gd")
const MusicBank := preload("res://src/audio/music_bank.gd")

const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_SFX: StringName = &"SFX"

const POOL_SIZE: int = 20
const MUSIC_FADE: float = 0.8
## Music sits under the effects.
const MUSIC_TRIM_DB: float = -5.0
## Track groups, one worker thread each (port first so the menu music arrives soonest).
const MUSIC_ORDER: Array[StringName] = [&"port", &"results", &"voyage"]
const MUSIC_THREADS: Array = [[&"port", &"results"], [&"voyage"]]

## Per-sound limits. `gap`: minimum seconds between plays. If a sound has `stack_db`, calls that
## arrive inside the gap still play (quieter, higher pitched) up to `burst` times per `window` s.
const DEFAULT_GAP: float = 0.03
const RATE_RULES: Dictionary = {
	&"coin": {"gap": 0.06, "stack_db": -9.0, "stack_pitch": 1.26, "burst": 3, "window": 0.3},
	&"mess_splat": {"gap": 0.1, "stack_db": -6.0, "stack_pitch": 1.12, "burst": 2, "window": 0.4},
	&"clean": {"gap": 0.1, "stack_db": -6.0, "stack_pitch": 1.12, "burst": 2, "window": 0.4},
	&"ui_hover": {"gap": 0.06},
	&"ui_click": {"gap": 0.04},
	&"slip": {"gap": 0.25},
	&"sick": {"gap": 0.25},
	&"error_buzz": {"gap": 0.2},
	&"breakdown": {"gap": 0.3},
	&"alert": {"gap": 0.3},
}

## SimWorld signal -> [sfx, volume_db]. Signals that need arguments are handled separately.
const SIM_SFX: Dictionary = {
	&"guest_stormed_off": [&"error_buzz", -3.0],
	&"guest_slipped": [&"slip", 0.0],
	&"guest_got_sick": [&"sick", 0.0],
	&"guest_cured": [&"cure", -3.0],
	&"room_broken": [&"breakdown", 0.0],
	&"room_repaired": [&"repair_done", 0.0],
	&"mess_spawned": [&"mess_splat", -2.0],
	&"mess_cleaned": [&"clean", 0.0],
	&"ghost_spawned": [&"ghost", 0.0],
	&"ghost_banished": [&"banish", 0.0],
	&"staff_tired": [&"alert", -12.0],
	&"event_started": [&"event_horn", 0.0],
	&"wave_started": [&"wave_board", 0.0],
	&"port_stop_started": [&"dock_horn", 0.0],
	&"port_stop_ended": [&"set_sail_horn", 0.0],
}

class MusicSlot:
	extends RefCounted
	var main: AudioStreamPlayer
	var perc: AudioStreamPlayer
	var track: StringName = &""
	var fade: float = 0.0
	var target: float = 0.0
	var fade_time: float = 0.8
	var has_perc: bool = false
	var loops: bool = true

## Set true before the node enters the tree to synthesise under --headless as well.
var synth_in_headless: bool = false
## Test hook: use this node instead of /root/Settings.
var settings_node: Node = null

var _sfx: Dictionary = {}          # StringName -> AudioStreamWAV
var _music: Dictionary = {}        # StringName -> {main, perc, loop}
var _pool: Array[AudioStreamPlayer] = []
var _pool_started: PackedFloat64Array = PackedFloat64Array()
var _last_play: Dictionary = {}
var _stack_times: Dictionary = {}
var _slots: Array[MusicSlot] = []
var _current_music: StringName = &""
var _requested_music: StringName = &""
var _requested_fade: float = MUSIC_FADE
var _intensity: float = 0.0
var _intensity_target: float = 0.0

var _amb_player: AudioStreamPlayer = null
var _amb_name: StringName = &""
var _amb_level: float = 0.0
var _amb_target: float = 0.0
var _sim_ref: WeakRef = null
var _sim_connections: Array = []   # [signal_name, Callable]
var _last_mutiny_warn: float = -100.0

var _threads: Array[Thread] = []
var _cancel: bool = false
var _pending_threads: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_pool.append(p)
		_pool_started.append(0.0)
	for i in 2:
		var s := MusicSlot.new()
		s.main = AudioStreamPlayer.new()
		s.main.bus = BUS_MUSIC
		s.main.volume_db = -80.0
		s.perc = AudioStreamPlayer.new()
		s.perc.bus = BUS_MUSIC
		s.perc.volume_db = -80.0
		add_child(s.main)
		add_child(s.perc)
		_slots.append(s)
	var settings := _settings()
	if settings != null and settings.has_signal("changed"):
		settings.connect("changed", _on_settings_changed)
	_apply_volumes()
	get_tree().node_added.connect(_on_node_added)
	_start_synth()
	set_process(false)


func _exit_tree() -> void:
	_cancel = true
	for t: Thread in _threads:
		if t.is_started():
			t.wait_to_finish()
	_threads.clear()
	unbind_sim()


# ---------------------------------------------------------------------------------------------
# Buses & volumes
# ---------------------------------------------------------------------------------------------

func _ensure_buses() -> void:
	for bus_name: StringName in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, BUS_MASTER)
	# Safety limiter on Master so a pile-up of sounds can never clip.
	var master: int = AudioServer.get_bus_index(BUS_MASTER)
	if master >= 0 and AudioServer.get_bus_effect_count(master) == 0:
		var fx: AudioEffect = null
		if ClassDB.class_exists(&"AudioEffectHardLimiter"):
			fx = ClassDB.instantiate(&"AudioEffectHardLimiter")
			fx.set("ceiling_db", -1.0)
		elif ClassDB.class_exists(&"AudioEffectLimiter"):
			fx = ClassDB.instantiate(&"AudioEffectLimiter")
			fx.set("ceiling_db", -1.0)
		if fx != null:
			AudioServer.add_bus_effect(master, fx)


func _settings() -> Node:
	if settings_node != null:
		return settings_node
	return get_node_or_null("/root/Settings")


func _on_settings_changed(key: StringName) -> void:
	if key == &"master_volume" or key == &"music_volume" or key == &"sfx_volume":
		_apply_volumes()


func _apply_volumes() -> void:
	var s := _settings()
	var vols: Dictionary = {
		BUS_MASTER: float(s.get("master_volume")) if s != null else 0.8,
		BUS_MUSIC: float(s.get("music_volume")) if s != null else 0.7,
		BUS_SFX: float(s.get("sfx_volume")) if s != null else 0.9,
	}
	for bus_name: StringName in vols:
		var idx: int = AudioServer.get_bus_index(bus_name)
		if idx < 0:
			continue
		var v: float = clampf(float(vols[bus_name]), 0.0, 1.0)
		AudioServer.set_bus_mute(idx, v <= 0.001)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))


# ---------------------------------------------------------------------------------------------
# Synthesis threads
# ---------------------------------------------------------------------------------------------

func _start_synth() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var headless: bool = DisplayServer.get_name() == "headless"
	if "--no-audio-synth" in args or (headless and not synth_in_headless and "--audio-synth" not in args):
		return
	# Single-threaded builds (the web export) can't run synthesis threads: load the pre-baked
	# sounds from tools/bake_audio.gd instead.
	if OS.has_feature("web") or "--audio-cache" in args:
		_load_baked_audio.call_deferred()
		return
	_pending_threads = 1 + MUSIC_THREADS.size()
	var sfx_thread := Thread.new()
	sfx_thread.start(_sfx_worker)
	_threads.append(sfx_thread)
	for group: Array in MUSIC_THREADS:
		var t := Thread.new()
		t.start(_music_worker.bind(group))
		_threads.append(t)


func _is_cancelled() -> bool:
	return _cancel


func _sfx_worker() -> void:
	for sfx_name: StringName in SfxBank.NAMES:
		if _cancel:
			return
		var b: PackedFloat32Array = SfxBank.render(sfx_name)
		_on_sfx_rendered.call_deferred(sfx_name, SU.to_pcm16(b))
	_on_thread_done.call_deferred()


func _music_worker(tracks: Array) -> void:
	for track_name: StringName in tracks:
		if _cancel:
			return
		var d: Dictionary = MusicBank.render(track_name, _is_cancelled)
		if d.is_empty():
			return
		var perc: PackedFloat32Array = d["perc"]
		_on_music_rendered.call_deferred(track_name, SU.to_pcm16(d["main"]),
			SU.to_pcm16(perc) if not perc.is_empty() else PackedByteArray(),
			bool(d["loop"]), int(d["sr"]))
	_on_thread_done.call_deferred()


const BAKED_AUDIO_DIR: String = "res://assets/audio_cache"


## Loads sounds pre-rendered by tools/bake_audio.gd. Missing files are skipped (that sound stays silent).
func _load_baked_audio() -> void:
	var manifest_path: String = BAKED_AUDIO_DIR.path_join("manifest.json")
	if not FileAccess.file_exists(manifest_path):
		push_warning("AudioManager: no baked audio at %s; the game will be silent" % BAKED_AUDIO_DIR)
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary:
		push_warning("AudioManager: unreadable baked audio manifest")
		return
	for sfx_name: StringName in SfxBank.NAMES:
		var sfx_stream: AudioStreamWAV = _load_baked_stream("sfx_%s.wav" % sfx_name, SfxBank.loop_frames(sfx_name))
		if sfx_stream != null:
			_sfx[sfx_name] = sfx_stream
			sfx_ready.emit(sfx_name)
	var music: Dictionary = (manifest as Dictionary).get("music", {})
	for track_key: String in music:
		var track_name := StringName(track_key)
		var info: Dictionary = music[track_key]
		var looped: bool = bool(info.get("loop", false))
		var main: AudioStreamWAV = _load_baked_stream("music_%s.wav" % track_key,
			int(info.get("frames", 0)) if looped else 0)
		if main == null:
			continue
		var perc_frames: int = int(info.get("perc_frames", 0))
		_music[track_name] = {
			"main": main,
			"perc": _load_baked_stream("music_%s_perc.wav" % track_key, perc_frames) if perc_frames > 0 else null,
			"loop": looped,
		}
		music_ready.emit(track_name)
		if _requested_music == track_name and _current_music != track_name:
			_start_music(track_name, _requested_fade)
	synth_finished.emit()


func _load_baked_stream(file: String, loop_frames: int) -> AudioStreamWAV:
	var path: String = BAKED_AUDIO_DIR.path_join(file)
	if not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStreamWAV
	if stream != null and loop_frames > 0:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = loop_frames
	return stream


func _on_thread_done() -> void:
	_pending_threads -= 1
	if _pending_threads <= 0:
		synth_finished.emit()


func _on_sfx_rendered(sfx_name: StringName, pcm: PackedByteArray) -> void:
	_sfx[sfx_name] = SU.make_stream(pcm, SU.SR_SFX, SfxBank.loop_frames(sfx_name))
	sfx_ready.emit(sfx_name)


func _on_music_rendered(track_name: StringName, pcm: PackedByteArray, perc_pcm: PackedByteArray,
		looped: bool, sr: int) -> void:
	var frames: int = pcm.size() / 2
	_music[track_name] = {
		"main": SU.make_stream(pcm, sr, frames if looped else 0),
		"perc": SU.make_stream(perc_pcm, sr, perc_pcm.size() / 2) if not perc_pcm.is_empty() else null,
		"loop": looped,
	}
	music_ready.emit(track_name)
	if _requested_music == track_name and _current_music != track_name:
		_start_music(track_name, _requested_fade)


## True once every sound effect and music track has been synthesised.
func is_ready() -> bool:
	return _sfx.size() >= SfxBank.NAMES.size() and _music.size() >= MUSIC_ORDER.size()


func has_sfx(sfx_name: StringName) -> bool:
	return _sfx.has(sfx_name)


func sfx_names() -> Array[StringName]:
	return SfxBank.NAMES.duplicate()


# ---------------------------------------------------------------------------------------------
# SFX
# ---------------------------------------------------------------------------------------------

## Plays a sound effect. `pitch_jitter` = +/- random pitch fraction; `volume_db` is added to the
## sound's own level. Unknown / not-yet-rendered names are ignored.
func play_sfx(sfx_name: StringName, pitch_jitter: float = 0.05, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _sfx.get(sfx_name)
	if stream == null:
		return
	var now: float = Time.get_ticks_usec() * 0.000001
	var rule: Dictionary = RATE_RULES.get(sfx_name, {})
	var gap: float = float(rule.get("gap", DEFAULT_GAP))
	var vol: float = volume_db
	var pitch_mult: float = 1.0
	if now - float(_last_play.get(sfx_name, -10.0)) < gap:
		if not rule.has("stack_db"):
			return
		var window: float = float(rule.get("window", 0.3))
		var times: Array = _stack_times.get(sfx_name, [])
		while not times.is_empty() and now - float(times[0]) > window:
			times.pop_front()
		if times.size() >= int(rule.get("burst", 2)):
			_stack_times[sfx_name] = times
			return
		times.append(now)
		_stack_times[sfx_name] = times
		vol += float(rule["stack_db"])
		pitch_mult = float(rule.get("stack_pitch", 1.0))
	else:
		_last_play[sfx_name] = now
	var p := _free_player(now)
	p.stream = stream
	p.volume_db = vol
	p.pitch_scale = maxf(0.1, (1.0 + randf_range(-pitch_jitter, pitch_jitter)) * pitch_mult)
	p.play()


## Looping ambience bed (the storm's rain): `level` 0..1 fades it in and out (call every frame or whenever it changes).
## `set_ambience(&"rain", 0.0)` lets it fade away.
func set_ambience(sfx_name: StringName, level: float) -> void:
	_amb_name = sfx_name
	_amb_target = clampf(level, 0.0, 1.0)
	set_process(true)


func _update_ambience(delta: float) -> bool:
	_amb_level = move_toward(_amb_level, _amb_target, delta / 1.5)
	if _amb_player == null:
		if _amb_level <= 0.0:
			return false
		_amb_player = AudioStreamPlayer.new()
		_amb_player.bus = BUS_SFX
		add_child(_amb_player)
	var stream: AudioStream = _sfx.get(_amb_name)
	if _amb_level <= 0.001 or stream == null:
		if _amb_player.playing:
			_amb_player.stop()
		return _amb_target > 0.0
	if _amb_player.stream != stream:
		_amb_player.stream = stream
	if not _amb_player.playing:
		_amb_player.play()
	_amb_player.volume_db = lerpf(-44.0, -6.0, _amb_level * _amb_level)
	return true


func _free_player(now: float) -> AudioStreamPlayer:
	var oldest: int = 0
	var oldest_t: float = INF
	for i in _pool.size():
		if not _pool[i].playing:
			_pool_started[i] = now
			return _pool[i]
		if _pool_started[i] < oldest_t:
			oldest_t = _pool_started[i]
			oldest = i
	_pool_started[oldest] = now
	return _pool[oldest]


## Results fanfare: jingle plus one star chime per star (0 stars / mutiny: a soft warning tone).
## Called automatically on SimWorld.voyage_ended when a sim is bound.
func play_results(stars: int, mutiny: bool = false) -> void:
	stop_music(0.4)
	if mutiny or stars <= 0:
		play_sfx(&"mutiny_warn", 0.0, -3.0)
		return
	play_music(&"results", 0.05)
	# star_1 / star_2 / star_3 are escalating chimes, one per star earned.
	for i in clampi(stars, 1, 3):
		var sfx_name := StringName("star_%d" % (i + 1))
		get_tree().create_timer(0.55 + 0.5 * i).timeout.connect(play_sfx.bind(sfx_name, 0.0, 0.0))


# ---------------------------------------------------------------------------------------------
# Music
# ---------------------------------------------------------------------------------------------

## Crossfades to a track ("port", "voyage", "results"). Safe to call before the track has finished
## rendering: it starts as soon as it is ready. Re-requesting the current track does nothing.
func play_music(track_name: StringName, fade: float = MUSIC_FADE) -> void:
	if track_name == &"":
		stop_music(fade)
		return
	_requested_music = track_name
	_requested_fade = fade
	if _current_music == track_name and _slot_playing(track_name) != null:
		return
	if _music.has(track_name):
		_start_music(track_name, fade)


## Fades the music out.
func stop_music(fade: float = MUSIC_FADE) -> void:
	_requested_music = &""
	_current_music = &""
	for s in _slots:
		s.target = 0.0
		s.fade_time = maxf(fade, 0.01)
	set_process(true)


func current_music() -> StringName:
	return _current_music


## 0..1: how loud the percussion layer of the voyage music is (the ship is "in trouble").
func set_music_intensity(value: float) -> void:
	_intensity_target = clampf(value, 0.0, 1.0)
	set_process(true)


func _slot_playing(track_name: StringName) -> MusicSlot:
	for s in _slots:
		if s.track == track_name and s.target > 0.0:
			return s
	return null


func _start_music(track_name: StringName, fade: float) -> void:
	var data: Dictionary = _music[track_name]
	# Fade everything else out.
	for s in _slots:
		s.target = 0.0
		s.fade_time = maxf(fade, 0.01)
	# Pick the quietest slot for the newcomer.
	var slot: MusicSlot = _slots[0]
	for s in _slots:
		if s.fade < slot.fade:
			slot = s
	slot.main.stop()
	slot.perc.stop()
	slot.track = track_name
	slot.loops = bool(data["loop"])
	slot.main.stream = data["main"]
	slot.has_perc = data["perc"] != null
	if slot.has_perc:
		slot.perc.stream = data["perc"]
	slot.fade = 0.0
	slot.target = 1.0
	slot.fade_time = maxf(fade, 0.01)
	slot.main.volume_db = -80.0
	slot.perc.volume_db = -80.0
	slot.main.play()
	if slot.has_perc:
		slot.perc.play()
	_current_music = track_name
	set_process(true)


func _process(delta: float) -> void:
	_intensity = move_toward(_intensity, _intensity_target, delta / 1.2)
	var any_active: bool = _update_ambience(delta)
	for s in _slots:
		s.fade = move_toward(s.fade, s.target, delta / s.fade_time)
		if s.target <= 0.0 and s.fade <= 0.0:
			if s.main.playing:
				s.main.stop()
			if s.perc.playing:
				s.perc.stop()
			continue
		any_active = true
		var g: float = sin(s.fade * PI * 0.5)  # equal-power crossfade
		s.main.volume_db = MUSIC_TRIM_DB + linear_to_db(maxf(g, 0.0001))
		if s.has_perc:
			s.perc.volume_db = MUSIC_TRIM_DB + linear_to_db(maxf(g * _intensity * 0.9, 0.0001))
		# One-shot track finished on its own.
		if s.target > 0.0 and not s.loops and not s.main.playing:
			s.target = 0.0
			s.fade = 0.0
			if _current_music == s.track:
				_current_music = &""
			music_finished.emit(s.track)
	if not any_active and is_equal_approx(_intensity, _intensity_target):
		set_process(false)


# ---------------------------------------------------------------------------------------------
# Automatic UI sounds
# ---------------------------------------------------------------------------------------------

func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.has_meta(&"no_ui_sound"):
		var btn := node as BaseButton
		btn.pressed.connect(_on_button_pressed.bind(btn))
		btn.mouse_entered.connect(_on_button_hover.bind(btn))


func _on_button_pressed(btn: BaseButton) -> void:
	if is_instance_valid(btn) and not btn.disabled and not btn.has_meta(&"no_ui_sound"):
		play_sfx(&"ui_click", 0.03)


func _on_button_hover(btn: BaseButton) -> void:
	if is_instance_valid(btn) and not btn.disabled and not btn.has_meta(&"no_ui_sound"):
		play_sfx(&"ui_hover", 0.04)


# ---------------------------------------------------------------------------------------------
# SimWorld binding
# ---------------------------------------------------------------------------------------------

## Connects to a SimWorld's signals (by name; missing signals are skipped). Rebinding replaces any
## previous binding. The results fanfare plays automatically on `voyage_ended`.
func bind_sim(sim: Object) -> void:
	unbind_sim()
	if sim == null:
		return
	_sim_ref = weakref(sim)
	_last_mutiny_warn = -100.0
	for sig: StringName in SIM_SFX:
		if sim.has_signal(sig):
			var info: Array = SIM_SFX[sig]
			_connect_sim(sim, sig, _unbound(_on_sim_simple.bind(info[0], float(info[1])), _signal_arity(sim, sig)))
	if sim.has_signal(&"room_used"):
		_connect_sim_args(sim, &"room_used", 3, _on_room_used, _on_sim_simple.bind(&"coin", 0.0))
	if sim.has_signal(&"money_changed"):
		_connect_sim_args(sim, &"money_changed", 3, _on_money_changed, Callable())
	if sim.has_signal(&"vip_boarded"):
		_connect_sim(sim, &"vip_boarded", _unbound(_on_sim_simple.bind(&"vip_arrive", 0.0), _signal_arity(sim, &"vip_boarded")))
	if sim.has_signal(&"vip_verdict"):
		_connect_sim_args(sim, &"vip_verdict", 3, _on_vip_verdict, Callable())
	if sim.has_signal(&"mutiny_warning"):
		_connect_sim_args(sim, &"mutiny_warning", 1, _on_mutiny_warning, _on_sim_simple.bind(&"mutiny_warn", 0.0))
	if sim.has_signal(&"mutiny_cleared"):
		_connect_sim(sim, &"mutiny_cleared", _unbound(_on_sim_simple.bind(&"cure", -3.0), _signal_arity(sim, &"mutiny_cleared")))
	if sim.has_signal(&"voyage_ended"):
		_connect_sim_args(sim, &"voyage_ended", 1, _on_voyage_ended, Callable())


## Disconnects everything bind_sim() connected.
func unbind_sim() -> void:
	var sim: Object = _sim_ref.get_ref() if _sim_ref != null else null
	if sim != null:
		for pair: Array in _sim_connections:
			if sim.is_connected(pair[0], pair[1]):
				sim.disconnect(pair[0], pair[1])
	_sim_connections.clear()
	_sim_ref = null


func _connect_sim(sim: Object, sig: StringName, cb: Callable) -> void:
	sim.connect(sig, cb)
	_sim_connections.append([sig, cb])


## Connects `handler` if the signal has exactly `expected` arguments, else the fallback (if valid).
func _connect_sim_args(sim: Object, sig: StringName, expected: int, handler: Callable, fallback: Callable) -> void:
	if _signal_arity(sim, sig) == expected:
		_connect_sim(sim, sig, handler)
	elif fallback.is_valid():
		_connect_sim(sim, sig, _unbound(fallback, _signal_arity(sim, sig)))


## Callable.unbind() rejects 0, so only wrap when the signal actually carries arguments.
static func _unbound(cb: Callable, count: int) -> Callable:
	return cb.unbind(count) if count > 0 else cb


static func _signal_arity(obj: Object, sig: StringName) -> int:
	for s: Dictionary in obj.get_signal_list():
		if StringName(s["name"]) == sig:
			return (s["args"] as Array).size()
	return 0


func _on_sim_simple(sfx_name: StringName, volume_db: float) -> void:
	play_sfx(sfx_name, 0.05, volume_db)


func _on_room_used(_room_uid: int, _guest_id: int, spend: int) -> void:
	if spend > 0:
		play_sfx(&"coin", 0.06)


func _on_money_changed(_money: int, _delta: int, reason: StringName) -> void:
	if reason == &"hires" or reason == &"hire":
		play_sfx(&"hire", 0.02)


func _on_vip_verdict(_guest_id: int, _kind: StringName, grade: StringName) -> void:
	match grade:
		&"great": play_sfx(&"vip_great", 0.02)
		&"bad": play_sfx(&"vip_bad", 0.02)
		_: play_sfx(&"vip_ok", 0.02)


func _on_mutiny_warning(_seconds_left: float) -> void:
	var now: float = Time.get_ticks_usec() * 0.000001
	if now - _last_mutiny_warn >= 3.5:
		_last_mutiny_warn = now
		play_sfx(&"mutiny_warn", 0.0)


func _on_voyage_ended(result: Dictionary) -> void:
	play_results(int(result.get("stars", 0)), bool(result.get("mutiny", false)))
