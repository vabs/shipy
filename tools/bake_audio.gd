extends SceneTree
## Pre-renders every procedural sound effect and music track to WAV files for builds that can't
## synthesise at runtime on worker threads (the single-threaded web export).
##
##   godot --headless --path . --script res://tools/bake_audio.gd
##   godot --headless --path . --import      # turns the WAVs into compressed audio resources
##
## Output: res://assets/audio_cache/{sfx_<name>,music_<track>,music_<track>_perc}.wav + manifest.json.
## AudioManager loads these on the web instead of starting synthesis threads.

const SU := preload("res://src/audio/synth_util.gd")
const SfxBank := preload("res://src/audio/sfx_bank.gd")
const MusicBank := preload("res://src/audio/music_bank.gd")

const OUT_DIR: String = "res://assets/audio_cache"


func _init() -> void:
	var err: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	if err != OK:
		push_error("bake_audio: cannot create %s (%d)" % [OUT_DIR, err])
		quit(1)
		return
	var ok: bool = true
	for sfx_name: StringName in SfxBank.NAMES:
		ok = _save("sfx_%s.wav" % sfx_name, SU.to_pcm16(SfxBank.render(sfx_name)), SfxBank.SR) and ok

	var music: Dictionary = {}
	for track: StringName in MusicBank.TRACKS:
		var d: Dictionary = MusicBank.render(track)
		var sr: int = int(d["sr"])
		var main_pcm: PackedByteArray = SU.to_pcm16(d["main"])
		ok = _save("music_%s.wav" % track, main_pcm, sr) and ok
		var info: Dictionary = {"loop": bool(d["loop"]), "frames": main_pcm.size() / 2, "perc_frames": 0}
		var perc: PackedFloat32Array = d["perc"]
		if not perc.is_empty():
			var perc_pcm: PackedByteArray = SU.to_pcm16(perc)
			ok = _save("music_%s_perc.wav" % track, perc_pcm, sr) and ok
			info["perc_frames"] = perc_pcm.size() / 2
		music[String(track)] = info

	var f := FileAccess.open(OUT_DIR.path_join("manifest.json"), FileAccess.WRITE)
	if f == null:
		push_error("bake_audio: cannot write manifest")
		quit(1)
		return
	f.store_string(JSON.stringify({"music": music}, "  "))
	f.close()
	print("AUDIO BAKED" if ok else "AUDIO BAKE FAILED")
	quit(0 if ok else 1)


func _save(file: String, pcm: PackedByteArray, sr: int) -> bool:
	var err: Error = SU.make_stream(pcm, sr).save_to_wav(OUT_DIR.path_join(file))
	if err != OK:
		push_error("bake_audio: could not write %s (%d)" % [file, err])
		return false
	return true
