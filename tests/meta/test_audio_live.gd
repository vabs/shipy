extends SceneTree
## End-to-end check of the threaded synthesis path of the real AudioManager autoload.
##
##   godot --headless --path . --script res://tests/meta/test_audio_live.gd -- --audio-synth
##
## (`--audio-synth` makes the autoload synthesise even under --headless.) Waits for
## `synth_finished`, then plays everything once and exercises music requests made *before* the
## loops finished rendering. Prints `AUDIO LIVE PASSED` / `AUDIO LIVE FAILED`.

const TIMEOUT_MS: int = 60000

var _fails: Array[String] = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var am: Node = root.get_node_or_null("AudioManager")
	if am == null:
		print("AUDIO LIVE FAILED: AudioManager autoload missing")
		quit(1)
		return
	if "--audio-synth" not in OS.get_cmdline_user_args():
		print("AUDIO LIVE FAILED: run with `-- --audio-synth`")
		quit(1)
		return
	var t0: int = Time.get_ticks_msec()
	# A request made before rendering finished must start by itself once the loop is ready.
	am.play_music(&"port")
	var done: Array[bool] = [false]
	am.synth_finished.connect(func() -> void: done[0] = true)
	while not done[0] and Time.get_ticks_msec() - t0 < TIMEOUT_MS:
		await process_frame
	var ms: int = Time.get_ticks_msec() - t0
	print("synthesis finished after %d ms (is_ready=%s)" % [ms, am.is_ready()])
	_check(done[0], "synth_finished never arrived")
	_check(am.is_ready(), "not every sound is ready")
	_check(am.current_music() == &"port", "pending port music request did not start")
	for sfx_name in am.sfx_names():
		_check(am.has_sfx(sfx_name), "missing sfx %s" % sfx_name)
		am.play_sfx(sfx_name, 0.0)
	am.play_music(&"voyage")
	_check(am.current_music() == &"voyage", "voyage did not start")
	am.set_music_intensity(1.0)
	for i in 10:
		await process_frame
	am.play_results(3)
	await process_frame
	_check(am.current_music() == &"results", "results jingle did not start")
	am.stop_music(0.05)
	for i in 10:
		await process_frame
	if _fails.is_empty():
		print("AUDIO LIVE PASSED")
		quit(0)
	else:
		for f in _fails:
			print("FAIL: ", f)
		print("AUDIO LIVE FAILED")
		quit(1)
