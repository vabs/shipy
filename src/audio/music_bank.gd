extends RefCounted
## Procedural music (docs/SPEC.md §8): two seamless loops plus a short "results" jingle, all
## synthesised from plucked/mallet voices, soft pads and filtered-noise percussion.
##
##   "port"    C major, 90 bpm, 16 bars (42.7 s): ukulele finger-picking, marimba tune, soft pad,
##             round bass, sea ambience, wind-chime runs at the phrase ends.
##   "voyage"  G major, 120 bpm, 32 bars (64 s): steel-drum lead (marimba doubling on the second
##             pass), off-beat ukulele stabs, bouncy bass, shaker. A second, separate PERCUSSION
##             layer (kick / clave / hat, same length) is returned so AudioManager can fade it in
##             with `set_music_intensity()`.
##   "results" ~3.8 s one-shot arpeggio + chord with bells (not looped).
##
## Loops are seamless: every note / echo / reverb tail wraps around the loop end (see
## SynthUtil.mix_wrap / loop_reverb) and noise beds are cross-faded, so there is no click and no
## gap at the boundary. `render()` is safe to call from a worker thread (no scene-tree access).

const SU := preload("res://src/audio/synth_util.gd")
const SR: int = SU.SR_MUSIC

const TRACKS: Array[StringName] = [&"port", &"voyage", &"results"]

## chord name -> [root pitch class, third interval]
const CHORDS: Dictionary = {
	"C": [0, 4], "Dm": [2, 3], "Em": [4, 3], "F": [5, 4], "G": [7, 4], "Am": [9, 3],
	"Bm": [11, 3], "D": [2, 4],
}

# ---- PORT (C major, 4/4, one string per bar: "NOTE:beats ..." / "r:beats") -----------------
const PORT_CHORDS: Array[String] = [
	"C", "Am", "F", "G", "C", "Em", "F", "G", "Am", "F", "C", "G", "F", "Em", "Dm", "G"]
const PORT_MELODY: Array[String] = [
	"E5:1.5 G5:.5 A5:1 G5:1",
	"E5:1 E5:.5 D5:.5 C5:1 r:1",
	"A5:1.5 G5:.5 F5:1 E5:1",
	"D5:2 r:1 B4:.5 D5:.5",
	"E5:1.5 G5:.5 C6:1 B5:1",
	"G5:1 A5:.5 G5:.5 E5:1 D5:1",
	"F5:1 A5:1 C6:1 A5:1",
	"G5:1.5 F5:.5 D5:1 r:1",
	"C6:1.5 B5:.5 A5:1 E5:1",
	"F5:1 A5:.5 C6:.5 A5:1 G5:1",
	"E5:.5 G5:.5 E5:1 D5:1 C5:1",
	"D5:1 G5:1 B5:1 A5:1",
	"A5:1.5 G5:.5 F5:1 A5:1",
	"G5:1 E5:1 G5:1 B5:1",
	"A5:1 F5:.5 A5:.5 D6:1 C6:1",
	"B5:1.5 A5:.5 G5:2",
]
## Ukulele finger-picking patterns: indices into [root, third, fifth, octave], -1 = rest.
const UKE_PATTERNS: Dictionary = {
	"A": [0, 2, 1, 2, 3, 2, 1, 2],
	"B": [0, 1, 2, 1, 3, 2, 1, 2],
	"C": [0, 2, 3, 2, 1, 2, -1, 2],
	"D": [0, 2, 1, 3, 2, 1, 0, -1],
}
const PORT_UKE: Array[String] = [
	"A", "B", "A", "C", "A", "B", "A", "C", "B", "A", "B", "C", "A", "B", "C", "D"]

# ---- VOYAGE (G major) ---------------------------------------------------------------------
const VOY_CHORDS_A: Array[String] = ["G", "Em", "C", "D", "G", "Em", "C", "D"]
const VOY_CHORDS_B: Array[String] = ["C", "D", "Bm", "Em", "C", "D", "G", "D"]
const VOY_MELODY_A: Array[String] = [
	"G5:.75 G5:.25 A5:.5 B5:.5 G5:1 r:.5 D5:.5",
	"E5:.75 G5:.25 B5:1 A5:.5 G5:.5 E5:1",
	"E5:.5 G5:.5 C6:1 B5:.5 G5:.5 E5:1",
	"D5:1 F#5:.5 A5:.5 A5:1.5 r:.5",
	"G5:.75 G5:.25 A5:.5 B5:.5 D6:1 B5:.5 A5:.5",
	"B5:.5 G5:.5 E5:1 G5:.5 B5:.5 A5:1",
	"C6:.75 B5:.25 A5:.5 G5:.5 E5:1 G5:.5 A5:.5",
	"A5:1.5 F#5:.5 D5:1 r:1",
]
const VOY_MELODY_B: Array[String] = [
	"E6:.75 D6:.25 C6:.5 B5:.5 G5:1 C6:.5 E5:.5",
	"D6:.75 C6:.25 A5:.5 F#5:.5 D5:1 F#5:.5 A5:.5",
	"B5:.75 D6:.25 F#6:1 D6:.5 B5:.5 A5:1",
	"G5:.5 B5:.5 E6:1 D6:.5 B5:.5 G5:1",
	"E6:1 C6:.5 G5:.5 E5:.75 G5:.25 C6:1",
	"D6:.5 A5:.5 F#5:.5 A5:.5 D6:1 C6:.5 A5:.5",
	"B5:.75 G5:.25 D5:.5 G5:.5 B5:1 D6:1",
	"A5:1 F#5:.5 A5:.5 D6:1 r:.5 B5:.5",
]
const VOY_MELODY_A2: Array[String] = [
	"B5:.75 B5:.25 C6:.5 D6:.5 B5:1 r:.5 G5:.5",
	"G5:.75 B5:.25 E6:1 D6:.5 B5:.5 G5:1",
	"G5:.5 C6:.5 E6:1 D6:.5 C6:.5 G5:1",
	"F#5:1 A5:.5 D6:.5 A5:1.5 r:.5",
	"D6:.75 D6:.25 E6:.5 D6:.5 B5:1 G5:.5 B5:.5",
	"G5:.5 E5:.5 G5:1 B5:.5 E6:.5 D6:1",
	"E6:.75 D6:.25 C6:.5 B5:.5 G5:1 E5:.5 G5:.5",
	"D5:.5 F#5:.5 A5:1 D6:1 r:1",
]
## Bass patterns: [beat, interval token, gain]. Tokens: R root, 5 fifth, 8 octave, 3 third.
const VOY_BASS: Dictionary = {
	"P1": [[0.0, "R", 1.0], [1.5, "5", 0.7], [2.0, "R", 0.9], [3.5, "5", 0.6]],
	"P2": [[0.0, "R", 1.0], [1.0, "8", 0.5], [1.5, "5", 0.7], [2.5, "R", 0.8], [3.0, "5", 0.6], [3.5, "3", 0.5]],
	"P3": [[0.0, "R", 1.0], [0.75, "R", 0.5], [1.5, "5", 0.7], [2.0, "R", 0.9], [2.75, "5", 0.5], [3.5, "3", 0.6]],
}
const VOY_BASS_ORDER: Array[String] = ["P1", "P2", "P1", "P3"]

var _cache: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _cancel: Callable = Callable()
var _spb: float = 0.0  # samples per beat


## Renders a track. Returns {"main": PackedFloat32Array, "perc": PackedFloat32Array (may be empty),
## "loop": bool, "sr": int}, or an empty Dictionary if unknown / cancelled.
## `cancel` (optional) is polled between bars; return true to abort.
static func render(track: StringName, cancel: Callable = Callable()) -> Dictionary:
	var m: RefCounted = (load("res://src/audio/music_bank.gd") as GDScript).new()
	m._cancel = cancel
	m._rng.seed = hash(String(track)) & 0x7fffffff
	match track:
		&"port": return m._render_port()
		&"voyage": return m._render_voyage()
		&"results": return m._render_results()
	return {}


## Parses "E5:1.5 G5:.5 r:1" into [[start_beat, midi (-1 = rest), length], ...].
static func parse_bar(s: String) -> Array:
	var out: Array = []
	var t: float = 0.0
	for tok in s.split(" ", false):
		var parts: PackedStringArray = tok.split(":")
		var len: float = float(parts[1])
		out.append([t, SU.note_midi(parts[0]), len])
		t += len
	return out


## Total beats in a bar string (should be 4.0).
static func bar_beats(s: String) -> float:
	var t: float = 0.0
	for e: Array in parse_bar(s):
		t += float(e[2])
	return t


func _cancelled() -> bool:
	return _cancel.is_valid() and bool(_cancel.call())


# ---------------------------------------------------------------------------------------------
# Instruments (each returns a peak-1 buffer, cached by pitch)
# ---------------------------------------------------------------------------------------------

func _pf(a: Array) -> PackedFloat32Array:
	return PackedFloat32Array(a)


func _uke(m: int, stab: bool = false) -> PackedFloat32Array:
	var key: String = "uke%d%s" % [m, "s" if stab else ""]
	if _cache.has(key):
		return _cache[key]
	var dm: float = 6.0 if stab else 1.0
	var b := SU.additive(SR, SU.hz(m), 0.2 if stab else 1.0,
		_pf([1.0, 2.0, 3.0, 4.0, 5.0, 6.0]), _pf([1.0, 0.62, 0.4, 0.22, 0.12, 0.06]),
		_pf([3.5 * dm, 5.0 * dm, 7.0 * dm, 10.0 * dm, 13.0 * dm, 16.0 * dm]), 0.002, 0.012)
	SU.normalize(b, 0.0)
	SU.mix_into(b, SU.noise(SR, 0.012, _rng, 3500.0, 1500.0, 300.0, 150.0, 0.0005), 0, 0.12)
	SU.normalize(b, 0.0)
	_cache[key] = b
	return b


func _marimba(m: int) -> PackedFloat32Array:
	var key: String = "mar%d" % m
	if _cache.has(key):
		return _cache[key]
	var b := SU.additive(SR, SU.hz(m), 0.8 if m < 74 else 0.55, _pf([1.0, 4.0, 10.0]),
		_pf([1.0, 0.5, 0.14]), _pf([4.5, 14.0, 30.0]), 0.0015, 0.015)
	SU.normalize(b, 0.0)
	SU.mix_into(b, SU.noise(SR, 0.006, _rng, 2500.0, 1200.0, 200.0, 200.0, 0.0004), 0, 0.1)
	SU.normalize(b, 0.0)
	_cache[key] = b
	return b


func _steel(m: int) -> PackedFloat32Array:
	var key: String = "stl%d" % m
	if _cache.has(key):
		return _cache[key]
	var f: float = SU.hz(m)
	var ratios := _pf([1.0, 2.0, 3.0, 4.01])
	var amps := _pf([1.0, 0.7, 0.38, 0.14])
	var decays := _pf([2.6, 3.4, 4.6, 7.0])
	var b := SU.additive(SR, f, 1.0, ratios, amps, decays, 0.004, 0.02)
	SU.mix_into(b, SU.additive(SR, f * 1.0017, 1.0, ratios, amps, decays, 0.004, 0.02), 0, 0.7)
	SU.normalize(b, 0.0)
	_cache[key] = b
	return b


func _bass(m: int, decay: float) -> PackedFloat32Array:
	var key: String = "bas%d_%d" % [m, int(decay * 10.0)]
	if _cache.has(key):
		return _cache[key]
	var b := SU.additive(SR, SU.hz(m), 0.8, _pf([1.0, 2.0, 3.0]), _pf([1.0, 0.38, 0.12]),
		_pf([decay, decay * 1.5, decay * 2.5]), 0.006, 0.02)
	SU.normalize(b, 0.0)
	_cache[key] = b
	return b


## Soft pad chord (3 voices, each a slightly detuned pair), sustained `dur` seconds + release.
func _pad(chord: String, dur: float) -> PackedFloat32Array:
	var key: String = "pad%s%d" % [chord, int(dur * 100.0)]
	if _cache.has(key):
		return _cache[key]
	var c: Array = CHORDS[chord]
	var r: int = _root_in(int(c[0]), 45)
	var notes: Array[int] = [r, r + 7, r + 12 + int(c[1])]
	var release: float = 0.7
	var b := SU.buf(int((dur + release) * SR))
	for m in notes:
		var v := SU.additive(SR, SU.hz(m), dur + release, _pf([1.0, 1.0035, 2.0]),
			_pf([0.5, 0.5, 0.1]), _pf([0.0, 0.0, 0.0]), 0.001, 0.001)
		SU.mix_into(b, v, 0, 1.0)
	SU.fade_in(b, int(0.4 * SR))
	SU.fade_out(b, int(release * SR))
	SU.normalize(b, 0.0)
	_cache[key] = b
	return b


func _shaker(accent: bool) -> PackedFloat32Array:
	var key: String = "shk%s" % accent
	if _cache.has(key):
		return _cache[key]
	var b := SU.noise(SR, 0.07, _rng, 9000.0, 9000.0, 3500.0, 55.0 if accent else 80.0, 0.004, 0.015)
	SU.normalize(b, 0.0)
	_cache[key] = b
	return b


func _hat() -> PackedFloat32Array:
	if _cache.has("hat"):
		return _cache["hat"]
	var b := SU.noise(SR, 0.05, _rng, 9500.0, 9500.0, 5500.0, 110.0, 0.001, 0.01)
	SU.normalize(b, 0.0)
	_cache["hat"] = b
	return b


func _kick() -> PackedFloat32Array:
	if _cache.has("kick"):
		return _cache["kick"]
	var b := SU.sweep(SR, 0.26, 130.0, 46.0, [1.0, 0.25], 0.002, 14.0, 0.1, 0.0, 0.0, 0.02)
	SU.normalize(b, 0.0)
	_cache["kick"] = b
	return b


func _clave() -> PackedFloat32Array:
	if _cache.has("clave"):
		return _cache["clave"]
	var b := SU.additive(SR, 1650.0, 0.1, _pf([1.0, 2.5]), _pf([1.0, 0.5]), _pf([70.0, 110.0]), 0.0008, 0.01)
	SU.normalize(b, 0.0)
	_cache["clave"] = b
	return b


func _bell(m: int, dur: float, decay: float) -> PackedFloat32Array:
	var key: String = "bel%d_%d" % [m, int(dur * 10.0)]
	if _cache.has(key):
		return _cache[key]
	var b := SU.additive(SR, SU.hz(m), dur, _pf([1.0, 2.0, 3.0, 4.2]), _pf([1.0, 0.3, 0.1, 0.04]),
		_pf([decay, decay * 1.7, decay * 2.6, decay * 4.0]), 0.002, 0.02)
	SU.normalize(b, 0.0)
	_cache[key] = b
	return b


# ---------------------------------------------------------------------------------------------
# Arrangement helpers
# ---------------------------------------------------------------------------------------------

static func _root_in(pc: int, lo: int) -> int:
	return lo + posmod(pc - lo, 12)


func _at(bar: int, beat: float) -> int:
	return int(round((bar * 4.0 + beat) * _spb))


func _jitter(ms: float) -> int:
	return int(_rng.randf_range(-ms, ms) * 0.001 * SR)


func _vel(base: float, spread: float = 0.07) -> float:
	return base * (1.0 + _rng.randf_range(-spread, spread))


## Plays one melody bar (mini-notation) with `inst` ("mar" | "stl") into `dst`, circularly.
func _play_melody_bar(dst: PackedFloat32Array, bar: int, text: String, inst: String, gain: float, transpose: int = 0) -> void:
	for e: Array in parse_bar(text):
		var m: int = int(e[1])
		if m < 0:
			continue
		m += transpose
		var beat: float = float(e[0])
		var note: PackedFloat32Array
		match inst:
			"stl": note = _steel(m)
			"bel": note = _bell(m, 0.9, 4.5)
			_: note = _marimba(m)
		var accent: float = 1.0 if is_equal_approx(beat, roundf(beat)) else 0.86
		SU.mix_wrap(dst, note, _at(bar, beat) + _jitter(5.0), gain * _vel(accent) * (1.08 if float(e[2]) >= 1.0 else 1.0))


func _bass_note(dst: PackedFloat32Array, chord: String, bar: int, beat: float, token: String, gain: float, decay: float) -> void:
	var c: Array = CHORDS[chord]
	var r: int = _root_in(int(c[0]), 42)
	var m: int = r
	match token:
		"5": m = r + 7
		"8": m = r + 12
		"3": m = r + int(c[1])
	SU.mix_wrap(dst, _bass(m, decay), _at(bar, beat) + _jitter(3.0), gain * _vel(1.0, 0.05))


# ---------------------------------------------------------------------------------------------
# PORT
# ---------------------------------------------------------------------------------------------

func _render_port() -> Dictionary:
	_spb = SR * 60.0 / 90.0
	var bars: int = PORT_CHORDS.size()
	var n: int = int(round(bars * 4.0 * _spb))
	var melodic := SU.buf(n)   # reverbed bed: pad + ukulele + marimba + chimes
	var mel := SU.buf(n)       # marimba tune (gets its own echoes)
	var low := SU.buf(n)       # bass (dry)

	for bar in bars:
		if _cancelled():
			return {}
		var chord: String = PORT_CHORDS[bar]
		var c: Array = CHORDS[chord]
		# Pad: a whole bar plus a little overlap so chords cross-fade.
		SU.mix_wrap(melodic, _pad(chord, 4.0 * 60.0 / 90.0 + 0.25), _at(bar, 0.0), 0.2)
		# Ukulele finger-picking.
		var r: int = _root_in(int(c[0]), 52)
		var tones: Array[int] = [r, r + int(c[1]), r + 7, r + 12]
		var pat: Array = UKE_PATTERNS[PORT_UKE[bar]]
		for slot in 8:
			var idx: int = pat[slot]
			if idx < 0:
				continue
			var base: float = 1.0 if slot == 0 else (0.8 if slot == 4 else 0.5)
			SU.mix_wrap(melodic, _uke(tones[idx]), _at(bar, slot * 0.5) + _jitter(6.0), 0.5 * _vel(base, 0.1))
		# Marimba tune.
		_play_melody_bar(mel, bar, PORT_MELODY[bar], "mar", 0.9)
		_play_melody_bar(mel, bar, PORT_MELODY[bar], "bel", 0.13, 12)  # toy-box sparkle an octave up
		# Bass: root on 1, fifth on 3 (gentle).
		_bass_note(low, chord, bar, 0.0, "R", 0.5, 3.0)
		_bass_note(low, chord, bar, 2.0, "5", 0.36, 3.2)
		if bar % 4 == 3:
			_bass_note(low, chord, bar, 3.5, "R", 0.22, 4.0)
		# Wind-chime run at the end of each 8-bar phrase (G major pentatonic: G A B D E).
		if bar % 8 == 7:
			var run: Array[int] = [79, 81, 83, 86, 88]
			for k in run.size():
				SU.mix_wrap(melodic, _bell(run[k], 0.9, 4.0), _at(bar, 3.0 + k * 0.17) + _jitter(4.0), 0.1 + 0.015 * k)

	# Echoes for the marimba tune (dotted-eighth and dotted-quarter taps), circularly.
	var mel_dry := mel.duplicate()
	SU.mix_wrap(mel, mel_dry, int(round(0.75 * _spb)), 0.26)
	SU.mix_wrap(mel, mel_dry, int(round(1.5 * _spb)), 0.12)
	SU.mix_into(melodic, mel, 0, 1.0)
	if _cancelled():
		return {}
	SU.loop_reverb(melodic, SR, 0.32)

	# Sea ambience: slow swells (3 per loop) of low-passed noise, cross-faded so it loops cleanly.
	var xf: int = int(0.25 * SR)
	var sea := SU.buf(n + xf)
	for i in sea.size():
		sea[i] = _rng.randf_range(-1.0, 1.0)
	SU.lowpass(sea, SR, 700.0)
	SU.lowpass(sea, SR, 500.0)
	SU.normalize(sea, 0.0)
	sea = SU.loopify(sea, n, xf)
	for i in n:
		sea[i] *= 0.55 + 0.45 * sin(TAU * 3.0 * float(i) / float(n) + 0.7)

	var main := SU.buf(n)
	for i in n:
		main[i] = melodic[i] + low[i] + sea[i] * 0.1
	SU.fit_loudness(main, -16.0, -1.5, -9.0)
	return {"main": main, "perc": PackedFloat32Array(), "loop": true, "sr": SR}


# ---------------------------------------------------------------------------------------------
# VOYAGE
# ---------------------------------------------------------------------------------------------

func _render_voyage() -> Dictionary:
	_spb = SR * 60.0 / 120.0
	var chords: Array[String] = []
	var melody: Array[String] = []
	chords.append_array(VOY_CHORDS_A)
	chords.append_array(VOY_CHORDS_B)
	chords.append_array(VOY_CHORDS_A)
	chords.append_array(VOY_CHORDS_B)
	melody.append_array(VOY_MELODY_A)
	melody.append_array(VOY_MELODY_B)
	melody.append_array(VOY_MELODY_A2)
	melody.append_array(VOY_MELODY_B)
	var bars: int = chords.size()
	var n: int = int(round(bars * 4.0 * _spb))
	var melodic := SU.buf(n)   # reverbed: lead + doubling + comping
	var lead := SU.buf(n)
	var low := SU.buf(n)
	var shake := SU.buf(n)
	var perc := SU.buf(n)

	for bar in bars:
		if _cancelled():
			return {}
		var chord: String = chords[bar]
		var c: Array = CHORDS[chord]
		var second_pass: bool = bar >= 16
		var b_section: bool = (bar % 16) >= 8

		# Lead: steel drum; the second pass doubles it with a marimba an octave up.
		_play_melody_bar(lead, bar, melody[bar], "stl", 0.9)
		if second_pass:
			_play_melody_bar(lead, bar, melody[bar], "mar", 0.4, 12)

		# Off-beat ukulele stabs ("skank") on the up-beats, accents on 2& and 4&.
		var r: int = _root_in(int(c[0]), 55)
		var voicing: Array[int] = [r + int(c[1]), r + 7, r + 12]
		for k in 4:
			var beat: float = 0.5 + k
			var v: float = 1.0 if (k == 1 or k == 3) else 0.6
			for j in voicing.size():
				SU.mix_wrap(melodic, _uke(voicing[j], true), _at(bar, beat) + j * int(0.007 * SR) + _jitter(4.0), 0.26 * _vel(v, 0.1))

		# Bass.
		var pat: Array = VOY_BASS[VOY_BASS_ORDER[bar % 4]]
		for step: Array in pat:
			_bass_note(low, chord, bar, float(step[0]), String(step[1]), 0.62 * float(step[2]), 5.5)

		# Shaker: steady eighths with an accent pattern; sixteenth ghost notes in B sections;
		# a crescendo roll at the end of each pass.
		for e in 8:
			var acc: bool = (e % 2 == 0)
			SU.mix_wrap(shake, _shaker(acc), _at(bar, e * 0.5) + _jitter(3.0), 0.5 * _vel(0.9 if acc else 0.5))
		if b_section:
			for e in 8:
				SU.mix_wrap(shake, _shaker(false), _at(bar, e * 0.5 + 0.25) + _jitter(3.0), 0.5 * _vel(0.22))
		if bar % 16 == 15:
			for e in 8:
				SU.mix_wrap(shake, _shaker(e % 2 == 0), _at(bar, 3.0 + e * 0.125), 0.5 * (0.3 + 0.1 * e))

		# Percussion layer (intensity): soft kick on 1 & 3, claves on a 3-3-2 figure, 16th hats.
		SU.mix_wrap(perc, _kick(), _at(bar, 0.0) + _jitter(2.0), 1.0)
		SU.mix_wrap(perc, _kick(), _at(bar, 2.0) + _jitter(2.0), 0.8)
		if b_section and bar % 2 == 1:
			SU.mix_wrap(perc, _kick(), _at(bar, 3.5) + _jitter(2.0), 0.55)
		for hit: float in [0.0, 1.5, 3.0]:
			SU.mix_wrap(perc, _clave(), _at(bar, hit) + _jitter(2.0), 0.55 * _vel(1.0))
		for e in 16:
			var hv: float = 0.3 if e % 4 == 2 else 0.16
			SU.mix_wrap(perc, _hat(), _at(bar, e * 0.25) + _jitter(2.0), hv * _vel(1.0, 0.15))

	# Lead echo (dotted-eighth) and shared room.
	var lead_dry := lead.duplicate()
	SU.mix_wrap(lead, lead_dry, int(round(0.75 * _spb)), 0.22)
	SU.mix_into(melodic, lead, 0, 1.0)
	if _cancelled():
		return {}
	SU.loop_reverb(melodic, SR, 0.24, 0.76, 0.4)

	var main := SU.buf(n)
	for i in n:
		main[i] = melodic[i] + low[i] + shake[i] * 0.16
	SU.fit_loudness(main, -16.0, -1.5, -9.0)
	SU.fit_loudness(perc, -21.0, -3.0, -10.0)
	return {"main": main, "perc": perc, "loop": true, "sr": SR}


# ---------------------------------------------------------------------------------------------
# RESULTS jingle (one-shot)
# ---------------------------------------------------------------------------------------------

func _render_results() -> Dictionary:
	var b := SU.buf(int(2.6 * SR))
	var notes: Array = [[0.0, 72, 0.85], [0.11, 76, 0.85], [0.22, 79, 0.85], [0.33, 84, 0.95]]
	for nt: Array in notes:
		SU.mix_into(b, _marimba(int(nt[1])), int(float(nt[0]) * SR), float(nt[2]))
	SU.mix_into(b, _bell(88, 1.4, 3.0), int(0.55 * SR), 0.6)
	SU.mix_into(b, _bell(91, 1.4, 3.0), int(0.66 * SR), 0.5)
	SU.mix_into(b, _bell(84, 1.6, 2.4), int(0.33 * SR), 0.45)
	# Warm chord underneath: C4 E4 G4 C5.
	var chord := SU.buf(int(2.3 * SR))
	for m: int in [60, 64, 67, 72]:
		SU.mix_into(chord, SU.additive(SR, SU.hz(m), 2.3, _pf([1.0, 1.003, 2.0]),
			_pf([0.5, 0.5, 0.08]), _pf([0.0, 0.0, 0.0]), 0.001, 0.001), 0, 1.0)
	SU.fade_in(chord, int(0.25 * SR))
	SU.fade_out(chord, int(1.2 * SR))
	SU.normalize(chord, 0.0)
	SU.mix_into(b, chord, int(0.3 * SR), 0.32)
	b = SU.echo(b, SR, [[0.22, 0.14], [0.44, 0.07]])
	b = SU.with_reverb(b, SR, 0.3, 1.0, 0.8, 0.4)
	SU.fit_loudness(b, -15.0, -1.5, -9.0)
	SU.fade_in(b, int(0.001 * SR))
	SU.fade_out(b, int(0.05 * SR))
	return {"main": b, "perc": PackedFloat32Array(), "loop": false, "sr": SR}
