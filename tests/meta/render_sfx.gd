extends SceneTree
## Renders every synthesised sound effect and music loop to WAV files for listening, and runs
## numeric sanity checks (peak <= -1 dBFS, no DC offset, clean start/end, seamless loop seams).
##
##   godot --headless --path . --script res://tests/meta/render_sfx.gd
##   godot --headless --path . --script res://tests/meta/render_sfx.gd -- --out=/some/dir
##
## Prints a table and `AUDIO RENDER OK` (exit 0) or `AUDIO RENDER FAILED` (exit 1).
## Files: sfx_<name>.wav, music_<track>_8s.wav (first 8 s), music_<track>_full.wav,
##        music_<track>_seam.wav (last 3 s + first 3 s of the loop, to hear the wrap),
##        music_voyage_perc_8s.wav (percussion layer alone) and music_voyage_mix_8s.wav (both).

const SU := preload("res://src/audio/synth_util.gd")
const SfxBank := preload("res://src/audio/sfx_bank.gd")
const MusicBank := preload("res://src/audio/music_bank.gd")

const DEFAULT_OUT: String = "res://tests/out/audio"

var _failures: Array[String] = []
var _out_dir: String = DEFAULT_OUT


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("Output dir: ", _out_dir)

	print("")
	print("%-14s %7s %9s %9s %10s %9s %9s" % ["sfx", "secs", "peak dB", "rms dB", "dc", "start", "end"])
	var t_all: int = Time.get_ticks_msec()
	for sfx_name in SfxBank.NAMES:
		var t0: int = Time.get_ticks_msec()
		var b: PackedFloat32Array = SfxBank.render(sfx_name)
		var ms: int = Time.get_ticks_msec() - t0
		_check_buffer(String(sfx_name), b, SfxBank.SR, false)
		_save("sfx_%s.wav" % sfx_name, b, SfxBank.SR)
		var st := SU.stats(b, SfxBank.SR)
		print("%-14s %7.2f %9.2f %9.2f %10.6f %9.5f %9.5f   (%d ms)" % [
			sfx_name, st["seconds"], st["peak_db"], st["rms_db"], st["dc"], b[0], b[b.size() - 1], ms])
	print("SFX total render: %d ms" % (Time.get_ticks_msec() - t_all))

	print("")
	for track in MusicBank.TRACKS:
		var t0: int = Time.get_ticks_msec()
		var d: Dictionary = MusicBank.render(track)
		var ms: int = Time.get_ticks_msec() - t0
		var main: PackedFloat32Array = d["main"]
		var sr: int = d["sr"]
		var looped: bool = d["loop"]
		var st := SU.stats(main, sr)
		print("music %-8s %6.2f s  peak %6.2f dB  rms %6.2f dB  dc %.6f  loop=%s  (%d ms)" % [
			track, st["seconds"], st["peak_db"], st["rms_db"], st["dc"], looped, ms])
		_check_buffer("music_" + String(track), main, sr, looped)
		_save("music_%s_full.wav" % track, main, sr)
		_save("music_%s_8s.wav" % track, main.slice(0, mini(main.size(), 8 * sr)), sr)
		if looped:
			var seam := main.slice(main.size() - 3 * sr)
			seam.append_array(main.slice(0, 3 * sr))
			_save("music_%s_seam.wav" % track, seam, sr)
		var perc: PackedFloat32Array = d["perc"]
		if not perc.is_empty():
			_check_buffer("music_%s_perc" % track, perc, sr, true)
			_save("music_%s_perc_8s.wav" % track, perc.slice(0, 8 * sr), sr)
			var mix := main.slice(0, 8 * sr)
			for i in mix.size():
				mix[i] += perc[i] * 0.9
			_save("music_%s_mix_8s.wav" % track, mix, sr)
			print("   perc layer: peak %.2f dB" % SU.stats(perc, sr)["peak_db"])

	print("")
	if _failures.is_empty():
		print("AUDIO RENDER OK")
		quit(0)
	else:
		for f in _failures:
			print("FAIL: ", f)
		print("AUDIO RENDER FAILED")
		quit(1)


func _save(file: String, b: PackedFloat32Array, sr: int) -> void:
	var stream := SU.make_stream(SU.to_pcm16(b), sr)
	var err: Error = stream.save_to_wav(_out_dir.path_join(file))
	if err != OK:
		_failures.append("could not write %s (%d)" % [file, err])


func _check_buffer(label: String, b: PackedFloat32Array, sr: int, looped: bool) -> void:
	if b.is_empty():
		_failures.append("%s: empty buffer" % label)
		return
	var peak_db: float = SU.to_db(SU.peak(b))
	if peak_db > -1.0:
		_failures.append("%s: peak %.2f dBFS exceeds -1" % [label, peak_db])
	var dc: float = absf(SU.mean(b))
	if dc > 0.002:
		_failures.append("%s: DC offset %.5f" % [label, dc])
	for i in b.size():
		if is_nan(b[i]) or is_inf(b[i]):
			_failures.append("%s: NaN/Inf at %d" % [label, i])
			break
	if looped:
		# Seamless loop: the jump across the wrap point must look like any ordinary sample step.
		var n: int = b.size()
		var jump: float = absf(b[0] - b[n - 1])
		var local_max: float = 0.0
		for i in range(1, 4000):
			local_max = maxf(local_max, absf(b[i] - b[i - 1]))
			local_max = maxf(local_max, absf(b[n - 1 - i] - b[n - 2 - i]))
		if jump > local_max * 1.5 + 1e-4:
			_failures.append("%s: loop seam jump %.5f vs local max step %.5f" % [label, jump, local_max])
	else:
		if absf(b[0]) > 0.01 or absf(b[b.size() - 1]) > 0.01:
			_failures.append("%s: edges not silent (start %.4f end %.4f)" % [label, b[0], b[b.size() - 1]])
