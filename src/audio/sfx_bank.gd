extends RefCounted
## Procedural sound effects (docs/SPEC.md §8). Every sound is synthesised from sine / triangle /
## soft-harmonic voices, filtered noise, pitch sweeps and small delayed-copy "room" tails so the
## whole set feels toy-like and gentle. `render(name)` returns a finished mono float buffer at
## SR (44.1 kHz): DC removed, faded, loudness-fitted to the sound's own RMS target with peaks soft-limited to -1.5 dBFS.
##
## Rendering is deterministic (seeded noise) and takes well under a second for the whole set.

const SU := preload("res://src/audio/synth_util.gd")
const SR: int = SU.SR_SFX

## Render order = priority (UI sounds first so menus are never silent while the rest renders).
const NAMES: Array[StringName] = [
	&"ui_click", &"ui_hover", &"place", &"coin", &"error_buzz", &"sell", &"upgrade", &"wave_board",
	&"hire", &"alert", &"mess_splat", &"clean", &"breakdown", &"repair_done", &"slip", &"sick",
	&"cure", &"ghost", &"banish", &"event_horn", &"star_1", &"star_2", &"star_3", &"mutiny_warn",
	&"set_sail_horn",
]

## Target loudness per sound as RMS in dBFS (peaks are soft-limited to -1.5 dBFS). UI sounds sit
## quiet, jingles and horns louder.
const LOUDNESS_DB: Dictionary = {
	&"ui_click": -22.0, &"ui_hover": -30.0, &"place": -19.0, &"coin": -21.0, &"error_buzz": -21.0,
	&"sell": -19.0, &"upgrade": -18.0, &"wave_board": -21.0, &"hire": -19.0, &"alert": -20.0,
	&"mess_splat": -20.0, &"clean": -22.0, &"breakdown": -19.0, &"repair_done": -19.0, &"slip": -19.0,
	&"sick": -21.0, &"cure": -19.0, &"ghost": -24.0, &"banish": -19.0, &"event_horn": -17.0,
	&"star_1": -19.0, &"star_2": -19.0, &"star_3": -18.0, &"mutiny_warn": -20.0, &"set_sail_horn": -16.0,
}


static func render(name: StringName) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(name)) & 0x7fffffff
	var b: PackedFloat32Array
	match name:
		&"ui_click": b = _ui_click()
		&"ui_hover": b = _ui_hover()
		&"place": b = _place(rng)
		&"sell": b = _sell(rng)
		&"upgrade": b = _upgrade(rng)
		&"coin": b = _coin()
		&"mess_splat": b = _mess_splat(rng)
		&"clean": b = _clean(rng)
		&"breakdown": b = _breakdown(rng)
		&"repair_done": b = _repair_done(rng)
		&"slip": b = _slip(rng)
		&"sick": b = _sick(rng)
		&"cure": b = _cure()
		&"ghost": b = _ghost(rng)
		&"banish": b = _banish(rng)
		&"alert": b = _alert()
		&"event_horn": b = _event_horn()
		&"star_1": b = _star_1()
		&"star_2": b = _star_2()
		&"star_3": b = _star_3()
		&"mutiny_warn": b = _mutiny_warn()
		&"set_sail_horn": b = _set_sail_horn()
		&"wave_board": b = _wave_board()
		&"error_buzz": b = _error_buzz()
		&"hire": b = _hire(rng)
		_:
			return PackedFloat32Array()
	SU.finish_sfx(b, SR, float(LOUDNESS_DB.get(name, -20.0)))
	return b


# ---------------------------------------------------------------------------------------------
# Building blocks
# ---------------------------------------------------------------------------------------------

static func _mk(dur: float) -> PackedFloat32Array:
	return SU.buf(int(dur * SR))


static func _put(dst: PackedFloat32Array, src: PackedFloat32Array, t: float, gain: float = 1.0) -> void:
	SU.mix_into(dst, src, int(t * SR), gain)


static func _pf(a: Array) -> PackedFloat32Array:
	return PackedFloat32Array(a)


## Glockenspiel / celesta-like bell.
static func _bell(f: float, dur: float, decay: float = 6.0) -> PackedFloat32Array:
	return SU.additive(SR, f, dur, _pf([1.0, 2.0, 3.0, 4.2]), _pf([1.0, 0.3, 0.1, 0.04]),
		_pf([decay, decay * 1.7, decay * 2.6, decay * 4.0]), 0.002)


## Marimba-ish mallet note (fundamental + the tuned 4x and 10x bar modes).
static func _mallet(f: float, dur: float, decay: float = 10.0) -> PackedFloat32Array:
	return SU.additive(SR, f, dur, _pf([1.0, 4.0, 10.0]), _pf([1.0, 0.3, 0.07]),
		_pf([decay, decay * 2.6, decay * 5.0]), 0.0015)


## Clean soft tone (sine + a whisper of 2nd harmonic).
static func _pure(f: float, dur: float, decay: float = 8.0) -> PackedFloat32Array:
	return SU.additive(SR, f, dur, _pf([1.0, 2.0]), _pf([1.0, 0.12]), _pf([decay, decay * 1.8]), 0.003)


static func _tick(rng: RandomNumberGenerator, lp: float = 4000.0, dur: float = 0.02) -> PackedFloat32Array:
	return SU.noise(SR, dur, rng, lp, lp * 0.5, 600.0, 90.0, 0.0005)


# ---------------------------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------------------------

static func _ui_click() -> PackedFloat32Array:
	return SU.sweep(SR, 0.07, 1050.0, 700.0, [1.0, 0.18], 0.0015, 60.0, 0.03)


static func _ui_hover() -> PackedFloat32Array:
	return SU.sweep(SR, 0.05, 1700.0, 1500.0, SU.H_SINE, 0.002, 70.0)


static func _error_buzz() -> PackedFloat32Array:
	var b := _mk(0.3)
	var a := SU.sweep(SR, 0.12, 311.0, 277.0, SU.H_TRI, 0.004, 12.0)
	SU.lowpass(a, SR, 1300.0)
	var c := SU.sweep(SR, 0.16, 262.0, 233.0, SU.H_TRI, 0.004, 11.0)
	SU.lowpass(c, SR, 1300.0)
	_put(b, a, 0.0, 1.0)
	_put(b, c, 0.13, 1.0)
	return b


static func _place(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _mk(0.34)
	_put(b, SU.sweep(SR, 0.22, 240.0, 110.0, SU.H_SOFT, 0.002, 24.0, 0.08), 0.0, 1.0)
	_put(b, _mallet(784.0, 0.3, 11.0), 0.02, 0.5)
	_put(b, SU.noise(SR, 0.1, rng, 3000.0, 800.0, 200.0, 40.0), 0.0, 0.25)
	return SU.with_reverb(b, SR, 0.18, 0.25, 0.7, 0.45)


static func _sell(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _mk(0.4)
	_put(b, _mallet(1047.0, 0.25, 12.0), 0.0, 0.9)
	_put(b, _mallet(784.0, 0.25, 12.0), 0.07, 0.8)
	_put(b, _mallet(659.0, 0.3, 11.0), 0.14, 0.8)
	_put(b, _bell(2637.0, 0.2, 14.0), 0.0, 0.14)
	_put(b, SU.noise(SR, 0.1, rng, 5000.0, 1500.0, 1200.0, 30.0), 0.0, 0.2)
	return SU.with_reverb(b, SR, 0.15, 0.25, 0.7, 0.45)


static func _upgrade(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _mk(0.8)
	var whoosh := SU.noise(SR, 0.28, rng, 500.0, 4200.0, 200.0, 0.0, 0.08)
	_put(b, whoosh, 0.0, 0.18)
	var notes: Array[float] = [523.25, 659.25, 783.99, 1046.5]
	for i in notes.size():
		_put(b, _mallet(notes[i], 0.45, 8.0), 0.06 + i * 0.075, 0.85)
	var chord_t: float = 0.06 + 3 * 0.075
	_put(b, _bell(1046.5, 0.55, 5.0), chord_t, 0.35)
	_put(b, _bell(1318.5, 0.55, 5.0), chord_t, 0.28)
	_put(b, _bell(1568.0, 0.55, 5.0), chord_t, 0.24)
	return SU.with_reverb(b, SR, 0.2, 0.3, 0.74, 0.4)


static func _coin() -> PackedFloat32Array:
	var b := _mk(0.38)
	_put(b, _bell(988.0, 0.14, 22.0), 0.0, 0.8)
	_put(b, _bell(1319.0, 0.32, 9.0), 0.065, 1.0)
	_put(b, _pure(2637.0, 0.18, 22.0), 0.065, 0.16)
	return b


static func _hire(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _mk(0.75)
	_put(b, _mallet(659.0, 0.18, 14.0), 0.0, 0.8)
	_put(b, _mallet(988.0, 0.18, 14.0), 0.08, 0.8)
	_put(b, _bell(1319.0, 0.5, 6.0), 0.17, 0.9)
	_put(b, SU.noise(SR, 0.12, rng, 6000.0, 2500.0, 1500.0, 30.0), 0.17, 0.2)
	return SU.with_reverb(b, SR, 0.2, 0.3, 0.72, 0.4)


## "Welcome aboard" ding-dong, played once per guest wave.
static func _wave_board() -> PackedFloat32Array:
	var b := _mk(0.9)
	_put(b, _bell(784.0, 0.5, 6.0), 0.0, 0.9)
	_put(b, _mallet(1568.0, 0.2, 16.0), 0.0, 0.25)
	_put(b, _bell(587.0, 0.7, 5.0), 0.2, 1.0)
	return SU.with_reverb(b, SR, 0.18, 0.3, 0.72, 0.4)


static func _alert() -> PackedFloat32Array:
	var b := _mk(0.5)
	var a := _pure(659.0, 0.18, 12.0)
	SU.mix_into(a, SU.sweep(SR, 0.18, 659.0, 659.0, SU.H_TRI, 0.003, 14.0), 0, 0.3)
	var c := _pure(988.0, 0.32, 7.0)
	SU.mix_into(c, SU.sweep(SR, 0.32, 988.0, 988.0, SU.H_TRI, 0.003, 9.0), 0, 0.25)
	_put(b, a, 0.0, 0.9)
	_put(b, c, 0.14, 1.0)
	return SU.with_reverb(b, SR, 0.12, 0.2, 0.7, 0.5)


# ---------------------------------------------------------------------------------------------
# Problems & fixes
# ---------------------------------------------------------------------------------------------

static func _mess_splat(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _mk(0.36)
	_put(b, SU.noise(SR, 0.3, rng, 4500.0, 400.0, 150.0, 14.0, 0.002), 0.0, 0.8)
	_put(b, SU.sweep(SR, 0.2, 300.0, 90.0, SU.H_SOFT, 0.003, 18.0), 0.0, 0.7)
	_put(b, SU.sweep(SR, 0.08, 500.0, 1100.0, SU.H_SINE, 0.003, 45.0, 0.05), 0.07, 0.35)
	return b


static func _clean(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _mk(0.55)
	var swoosh := SU.noise(SR, 0.3, rng, 600.0, 5000.0, 300.0, 6.0, 0.1)
	_put(b, swoosh, 0.0, 0.5)
	_put(b, _bell(2093.0, 0.25, 14.0), 0.08, 0.35)
	_put(b, _bell(2637.0, 0.25, 14.0), 0.15, 0.32)
	_put(b, _bell(3136.0, 0.3, 12.0), 0.22, 0.3)
	return SU.with_reverb(b, SR, 0.15, 0.25, 0.72, 0.3)


static func _breakdown(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _mk(0.85)
	_put(b, SU.sweep(SR, 0.3, 160.0, 55.0, [1.0, 0.4, 0.15], 0.002, 14.0, 0.12), 0.0, 1.0)
	var wah := SU.sweep(SR, 0.5, 330.0, 196.0, SU.H_TRI, 0.01, 4.5, 0.38, 6.0, 0.04)
	SU.lowpass(wah, SR, 1400.0)
	_put(b, wah, 0.12, 0.45)
	for t: float in [0.3, 0.4, 0.47]:
		_put(b, SU.noise(SR, 0.04, rng, 2000.0, 1500.0, 500.0, 90.0, 0.001), t, 0.35)
	return SU.with_reverb(b, SR, 0.14, 0.25, 0.7, 0.5)


static func _repair_done(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _mk(0.85)
	for i in 4:
		_put(b, _tick(rng, 5200.0, 0.022), i * 0.05, 1.1)
	_put(b, _bell(784.0, 0.3, 8.0), 0.2, 0.7)
	_put(b, _bell(1047.0, 0.5, 6.0), 0.28, 0.95)
	_put(b, _bell(2637.0, 0.3, 14.0), 0.3, 0.18)
	return SU.with_reverb(b, SR, 0.18, 0.3, 0.72, 0.4)


static func _slip(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _mk(0.62)
	_put(b, SU.sweep(SR, 0.4, 1500.0, 300.0, [1.0, 0.12], 0.01, 3.0, 0.35, 9.0, 0.02), 0.0, 0.8)
	_put(b, SU.sweep(SR, 0.2, 150.0, 70.0, SU.H_SOFT, 0.001, 20.0, 0.1), 0.36, 0.9)
	_put(b, SU.noise(SR, 0.1, rng, 900.0, 300.0, 100.0, 50.0), 0.36, 0.5)
	return b


static func _sick(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _mk(0.7)
	var wob := SU.sweep(SR, 0.6, 330.0, 190.0, SU.H_TRI, 0.03, 2.5, 0.5, 5.5, 0.12)
	SU.lowpass(wob, SR, 900.0)
	_put(b, wob, 0.0, 1.0)
	_put(b, SU.noise(SR, 0.35, rng, 500.0, 250.0, 100.0, 6.0, 0.05), 0.2, 0.12)
	return b


static func _cure() -> PackedFloat32Array:
	var b := _mk(0.9)
	var notes: Array[float] = [784.0, 1047.0, 1319.0, 1568.0]
	for i in notes.size():
		_put(b, _bell(notes[i], 0.65, 5.5), i * 0.06, 0.8 - 0.08 * i)
	var pad := SU.additive(SR, 523.25, 0.7, _pf([1.0, 1.5]), _pf([1.0, 0.7]), _pf([0.0, 0.0]), 0.2, 0.3)
	_put(b, pad, 0.05, 0.22)
	return SU.with_reverb(b, SR, 0.22, 0.4, 0.76, 0.4)


static func _ghost(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _mk(1.1)
	var v1 := SU.sweep(SR, 1.0, 330.0, 262.0, [1.0, 0.15, 0.05], 0.15, 0.0, 0.9, 5.0, 0.03, 0.2)
	var v2 := SU.sweep(SR, 1.0, 335.0, 266.0, [1.0, 0.15, 0.05], 0.15, 0.0, 0.9, 4.6, 0.03, 0.2)
	SU.mix_into(v1, v2, 0, 0.8)
	SU.mix_into(v1, SU.noise(SR, 1.0, rng, 1200.0, 600.0, 400.0, 0.0, 0.2, 0.2), 0, 0.08)
	SU.swell(v1, 1.4)
	_put(b, v1, 0.0, 1.0)
	return SU.echo(SU.with_reverb(b, SR, 0.3, 0.5, 0.8, 0.35), SR, [[0.18, 0.4], [0.36, 0.22]])


static func _banish(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _mk(0.8)
	_put(b, SU.sweep(SR, 0.25, 500.0, 2400.0, [1.0, 0.3, 0.1], 0.004, 9.0, 0.18), 0.0, 0.8)
	_put(b, _bell(2093.0, 0.4, 8.0), 0.15, 0.3)
	_put(b, _bell(3136.0, 0.4, 8.0), 0.18, 0.22)
	_put(b, SU.noise(SR, 0.22, rng, 3500.0, 500.0, 300.0, 14.0), 0.2, 0.6)
	_put(b, SU.sweep(SR, 0.07, 300.0, 800.0, SU.H_SINE, 0.003, 40.0, 0.05), 0.4, 0.4)
	return SU.with_reverb(b, SR, 0.2, 0.3, 0.74, 0.4)


# ---------------------------------------------------------------------------------------------
# Events, results, alarms
# ---------------------------------------------------------------------------------------------

static func _horn(f: float, dur: float, vib_hz: float, vib_depth: float, cutoff: float) -> PackedFloat32Array:
	var h := SU.sweep(SR, dur, f * 0.9, f, SU.H_BRASS, 0.025, 1.2, 0.07, vib_hz, vib_depth, 0.06)
	SU.lowpass(h, SR, cutoff)
	return h


static func _event_horn() -> PackedFloat32Array:
	var b := _mk(1.0)
	_put(b, _horn(233.1, 0.28, 0.0, 0.0, 1500.0), 0.0, 0.85)
	_put(b, _horn(311.1, 0.55, 5.5, 0.01, 1500.0), 0.33, 1.0)
	return SU.with_reverb(b, SR, 0.2, 0.4, 0.76, 0.5)


static func _set_sail_horn() -> PackedFloat32Array:
	var b := _mk(1.9)
	var chord := _horn(116.5, 1.6, 0.0, 0.0, 1400.0)
	SU.mix_into(chord, _horn(174.6, 1.6, 0.0, 0.0, 1400.0), 0, 0.7)
	SU.mix_into(chord, _horn(233.1, 1.6, 0.0, 0.0, 1400.0), 0, 0.45)
	SU.fade_in(chord, int(0.08 * SR))
	SU.fade_out(chord, int(0.5 * SR))
	_put(b, chord, 0.0, 1.0)
	return SU.with_reverb(b, SR, 0.28, 0.7, 0.8, 0.4)


static func _star_1() -> PackedFloat32Array:
	var b := _mk(1.0)
	_put(b, _bell(1047.0, 1.0, 3.2), 0.0, 1.0)
	_put(b, _bell(2093.0, 0.8, 4.0), 0.0, 0.25)
	_put(b, _pure(2637.0, 0.5, 9.0), 0.1, 0.12)
	return SU.with_reverb(b, SR, 0.25, 0.5, 0.78, 0.4)


static func _star_2() -> PackedFloat32Array:
	var b := _mk(1.2)
	_put(b, _bell(1047.0, 0.8, 3.5), 0.0, 0.9)
	_put(b, _bell(1568.0, 1.0, 3.2), 0.16, 1.0)
	_put(b, _bell(3136.0, 0.7, 4.0), 0.16, 0.2)
	_put(b, _pure(2637.0, 0.5, 9.0), 0.26, 0.12)
	return SU.with_reverb(b, SR, 0.25, 0.5, 0.78, 0.4)


static func _star_3() -> PackedFloat32Array:
	var b := _mk(1.8)
	var notes: Array[float] = [523.25, 659.25, 783.99, 1046.5, 1318.5]
	for i in notes.size():
		_put(b, _bell(notes[i], 1.0, 4.5), i * 0.09, 0.8)
	var t: float = 0.5
	_put(b, _bell(1046.5, 1.2, 2.5), t, 0.5)
	_put(b, _bell(1318.5, 1.2, 2.5), t, 0.42)
	_put(b, _bell(1568.0, 1.2, 2.5), t, 0.4)
	_put(b, _bell(2093.0, 0.9, 3.5), t + 0.05, 0.22)
	_put(b, _pure(3136.0, 0.6, 8.0), t + 0.1, 0.1)
	return SU.with_reverb(b, SR, 0.28, 0.6, 0.8, 0.4)


static func _mutiny_warn() -> PackedFloat32Array:
	var b := _mk(1.0)
	var freqs: Array[float] = [220.0, 196.0, 175.0]
	for i in freqs.size():
		var pulse := SU.sweep(SR, 0.32, freqs[i], freqs[i] * 0.87, [1.0, 0.5, 0.2], 0.01, 9.0, 0.25)
		SU.lowpass(pulse, SR, 1100.0)
		_put(b, pulse, i * 0.27, 1.0)
		_put(b, _pure(freqs[i] * 4.0, 0.12, 22.0), i * 0.27, 0.12)
	return SU.with_reverb(b, SR, 0.16, 0.3, 0.74, 0.5)
