extends RefCounted
## Tiny DSP toolkit for the procedural audio (no class_name on purpose: other scripts
## `preload()` this file so no global-class-cache refresh is needed).
##
## All buffers are mono `PackedFloat32Array` in -1..1. Functions that fill or modify a buffer work
## in place (packed arrays are passed by reference); functions that change the length either
## grow the buffer they are given or return a new one (stated per function).

const SR_SFX: int = 44100
const SR_MUSIC: int = 22050

## Harmonic amplitude tables for `sweep()` (index 0 = fundamental).
const H_SINE: Array[float] = [1.0]
const H_SOFT: Array[float] = [1.0, 0.22]
const H_TRI: Array[float] = [1.0, 0.0, -0.111, 0.0, 0.04, 0.0, -0.0204]
const H_BRASS: Array[float] = [1.0, 0.8, 0.6, 0.42, 0.28, 0.18, 0.1, 0.05]


# ---------------------------------------------------------------------------------------------
# Basics
# ---------------------------------------------------------------------------------------------

static func buf(n: int) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(maxi(0, n))
	return b


static func hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


## "C4" -> 60, "F#3" -> 54, "Bb5" -> 82. Returns -1 for rests ("r") / bad input.
static func note_midi(name: String) -> int:
	var s: String = name.strip_edges()
	if s.length() < 2:
		return -1
	var base: int
	match s.substr(0, 1).to_upper():
		"C": base = 0
		"D": base = 2
		"E": base = 4
		"F": base = 5
		"G": base = 7
		"A": base = 9
		"B": base = 11
		_: return -1
	var i: int = 1
	while i < s.length() and (s[i] == "#" or s[i] == "b"):
		base += 1 if s[i] == "#" else -1
		i += 1
	if not s.substr(i).is_valid_int():
		return -1
	return 12 * (int(s.substr(i)) + 1) + base


static func peak(b: PackedFloat32Array) -> float:
	var p: float = 0.0
	for i in b.size():
		var v: float = absf(b[i])
		if v > p:
			p = v
	return p


static func mean(b: PackedFloat32Array) -> float:
	if b.is_empty():
		return 0.0
	var s: float = 0.0
	for i in b.size():
		s += b[i]
	return s / b.size()


static func rms(b: PackedFloat32Array) -> float:
	if b.is_empty():
		return 0.0
	var s: float = 0.0
	for i in b.size():
		s += b[i] * b[i]
	return sqrt(s / b.size())


static func to_db(linear: float) -> float:
	return 20.0 * log(maxf(linear, 1e-9)) / log(10.0)


static func remove_dc(b: PackedFloat32Array) -> void:
	var m: float = mean(b)
	if absf(m) < 1e-9:
		return
	for i in b.size():
		b[i] -= m


## Scales so the absolute peak equals `peak_db` dBFS.
static func normalize(b: PackedFloat32Array, peak_db: float) -> void:
	var p: float = peak(b)
	if p < 1e-9:
		return
	var g: float = pow(10.0, peak_db / 20.0) / p
	for i in b.size():
		b[i] *= g


static func scale(b: PackedFloat32Array, g: float) -> void:
	for i in b.size():
		b[i] *= g


## Raised-cosine fade in over the first `n` samples.
static func fade_in(b: PackedFloat32Array, n: int) -> void:
	n = mini(n, b.size())
	for i in n:
		b[i] *= 0.5 - 0.5 * cos(PI * float(i) / float(n))


## Raised-cosine fade out over the last `n` samples (ends at exactly 0).
static func fade_out(b: PackedFloat32Array, n: int) -> void:
	var size: int = b.size()
	n = mini(n, size)
	for i in n:
		b[size - 1 - i] *= 0.5 - 0.5 * cos(PI * float(i) / float(n))


## Multiplies by sin(pi * t / T) ** power (a smooth swell: silent at both ends).
static func swell(b: PackedFloat32Array, power: float = 1.0) -> void:
	var n: int = b.size()
	for i in n:
		b[i] *= pow(sin(PI * (float(i) + 0.5) / float(n)), power)


## Adds `src * gain` into `dst` starting at sample `offset`. Grows `dst` when needed.
static func mix_into(dst: PackedFloat32Array, src: PackedFloat32Array, offset: int, gain: float = 1.0) -> void:
	var m: int = src.size()
	if offset < 0:
		return
	if offset + m > dst.size():
		dst.resize(offset + m)
	for j in m:
		dst[offset + j] += src[j] * gain


## Adds `src * gain` into `dst` starting at `offset`, wrapping around the end (for seamless loops).
static func mix_wrap(dst: PackedFloat32Array, src: PackedFloat32Array, offset: int, gain: float = 1.0) -> void:
	var n: int = dst.size()
	var m: int = src.size()
	if n == 0:
		return
	var start: int = posmod(offset, n)
	var first: int = mini(m, n - start)
	for j in first:
		dst[start + j] += src[j] * gain
	var j2: int = first
	var pos: int = 0
	while j2 < m:  # only when the note is longer than the space left (rare: wraps once or more)
		dst[pos] += src[j2] * gain
		pos += 1
		if pos >= n:
			pos = 0
		j2 += 1


## One-pole low-pass in place.
static func lowpass(b: PackedFloat32Array, sr: int, fc: float) -> void:
	var a: float = 1.0 - exp(-TAU * fc / sr)
	var y: float = 0.0
	for i in b.size():
		y += a * (b[i] - y)
		b[i] = y


## One-pole high-pass in place.
static func highpass(b: PackedFloat32Array, sr: int, fc: float) -> void:
	var a: float = 1.0 - exp(-TAU * fc / sr)
	var y: float = 0.0
	for i in b.size():
		y += a * (b[i] - y)
		b[i] -= y


# ---------------------------------------------------------------------------------------------
# Oscillators / generators
# ---------------------------------------------------------------------------------------------

## Additive note: parallel decaying sine partials. `ratios[k]` multiplies `f`; `amps[k]` is the
## starting amplitude; `decays[k]` is the exponential decay rate per second (0 = sustained).
static func additive(sr: int, f: float, length: float, ratios: PackedFloat32Array,
		amps: PackedFloat32Array, decays: PackedFloat32Array, attack: float = 0.002,
		release: float = 0.012) -> PackedFloat32Array:
	var n: int = int(length * sr)
	var out := buf(n)
	for k in ratios.size():
		var fk: float = f * ratios[k]
		if fk >= sr * 0.45:
			continue
		var w: float = TAU * fk / sr
		var env: float = amps[k]
		var mul: float = exp(-decays[k] / sr)
		var ph: float = 0.0
		for i in n:
			out[i] += env * sin(ph)
			ph += w
			env *= mul
	fade_in(out, int(attack * sr))
	fade_out(out, int(release * sr))
	return out


## Single voice with an exponential pitch sweep from `f0` to `f1` over `sweep_time` seconds
## (< 0 = the whole duration), then holding `f1`. Harmonics from `harm` (index 0 = fundamental),
## exponential amplitude decay `decay` per second (0 = sustained), optional vibrato.
static func sweep(sr: int, dur: float, f0: float, f1: float, harm: Array, attack: float,
		decay: float, sweep_time: float = -1.0, vib_hz: float = 0.0, vib_depth: float = 0.0,
		release: float = 0.012) -> PackedFloat32Array:
	var n: int = int(dur * sr)
	var out := buf(n)
	var sweep_n: int = n if sweep_time < 0.0 else int(sweep_time * sr)
	sweep_n = maxi(1, mini(sweep_n, n))
	var ratio: float = pow(f1 / f0, 1.0 / sweep_n)
	var f: float = f0
	var ph: float = 0.0
	var env: float = 1.0
	var emul: float = exp(-decay / sr)
	var vph: float = 0.0
	var vw: float = TAU * vib_hz / sr
	var nh: int = harm.size()
	var amps := PackedFloat32Array()
	for k in nh:
		amps.append(float(harm[k]))
	for i in n:
		var ff: float = f
		if vib_depth > 0.0:
			ff = f * (1.0 + vib_depth * sin(vph))
			vph += vw
		ph += TAU * ff / sr
		var s: float = 0.0
		for k in nh:
			var a: float = amps[k]
			if a != 0.0:
				s += a * sin(ph * (k + 1))
		out[i] = s * env
		env *= emul
		if i < sweep_n:
			f *= ratio
	fade_in(out, int(attack * sr))
	fade_out(out, int(release * sr))
	return out


## Filtered noise burst. The low-pass cutoff sweeps exponentially `lp0` -> `lp1`; `hp` is a
## one-pole high-pass cutoff (0 = off); exponential decay per second.
static func noise(sr: int, dur: float, rng: RandomNumberGenerator, lp0: float, lp1: float,
		hp: float, decay: float, attack: float = 0.002, release: float = 0.012) -> PackedFloat32Array:
	var n: int = int(dur * sr)
	var out := buf(n)
	var ratio: float = pow(lp1 / lp0, 1.0 / maxf(1.0, n - 1.0))
	var fc: float = lp0
	var y1: float = 0.0
	var y2: float = 0.0
	var env: float = 1.0
	var emul: float = exp(-decay / sr)
	var ha: float = 1.0 - exp(-TAU * hp / sr) if hp > 0.0 else 0.0
	var hz_state: float = 0.0
	for i in n:
		var a: float = 1.0 - exp(-TAU * minf(fc, sr * 0.45) / sr)
		var x: float = rng.randf_range(-1.0, 1.0)
		y1 += a * (x - y1)
		y2 += a * (y1 - y2)
		var v: float = y2
		if hp > 0.0:
			hz_state += ha * (v - hz_state)
			v -= hz_state
		out[i] = v * env
		env *= emul
		fc *= ratio
	fade_in(out, int(attack * sr))
	fade_out(out, int(release * sr))
	return out


# ---------------------------------------------------------------------------------------------
# Space: echoes and reverb
# ---------------------------------------------------------------------------------------------

## Returns `b` plus feed-forward delayed copies. `taps` = [[delay_seconds, gain], ...]. The
## result is longer than the input by the longest delay.
static func echo(b: PackedFloat32Array, sr: int, taps: Array) -> PackedFloat32Array:
	var n: int = b.size()
	var longest: int = 0
	for t: Array in taps:
		longest = maxi(longest, int(float(t[0]) * sr))
	var out := b.duplicate()
	out.resize(n + longest)
	for t: Array in taps:
		var d: int = int(float(t[0]) * sr)
		var g: float = float(t[1])
		for i in n:
			out[i + d] += b[i] * g
	return out


## Freeverb-style room: 4 damped feedback combs + 2 all-passes. Returns the WET signal only, same
## length as `src`. `feedback` ~0.70 (tiny) .. 0.88 (hall); `damp` 0..1 (higher = darker).
static func reverb_wet(src: PackedFloat32Array, sr: int, feedback: float = 0.74, damp: float = 0.35) -> PackedFloat32Array:
	var n: int = src.size()
	var out := buf(n)
	var scale_sr: float = float(sr) / 44100.0
	var comb_len: Array[int] = [
		int(1116.0 * scale_sr), int(1188.0 * scale_sr), int(1277.0 * scale_sr), int(1356.0 * scale_sr)]
	for c in comb_len.size():
		var d: int = comb_len[c]
		var line := buf(d)
		var idx: int = 0
		var filt: float = 0.0
		for i in n:
			var stored: float = line[idx]
			filt = stored * (1.0 - damp) + filt * damp
			line[idx] = src[i] * 0.2 + filt * feedback
			out[i] += stored
			idx += 1
			if idx >= d:
				idx = 0
	var ap_len: Array[int] = [int(556.0 * scale_sr), int(441.0 * scale_sr)]
	for a in ap_len.size():
		var d2: int = ap_len[a]
		var line2 := buf(d2)
		var idx2: int = 0
		for i in n:
			var delayed: float = line2[idx2]
			var x: float = out[i]
			line2[idx2] = x + delayed * 0.5
			out[i] = delayed - x
			idx2 += 1
			if idx2 >= d2:
				idx2 = 0
	return out


## `b` + reverb, extended by `tail` seconds so the reverb can ring out. Returns a new buffer.
static func with_reverb(b: PackedFloat32Array, sr: int, wet: float, tail: float = 0.5,
		feedback: float = 0.74, damp: float = 0.35) -> PackedFloat32Array:
	var src := b.duplicate()
	src.resize(b.size() + int(tail * sr))
	var w := reverb_wet(src, sr, feedback, damp)
	for i in src.size():
		src[i] += w[i] * wet
	return src


## Reverb for a seamless loop: the buffer is pre-rolled with its own tail so the reverb of the
## last bars bleeds into the first ones. Modifies `b` in place (adds `wet` * reverb).
static func loop_reverb(b: PackedFloat32Array, sr: int, wet: float, feedback: float = 0.80, damp: float = 0.4) -> void:
	var n: int = b.size()
	var pre: int = mini(n, int(2.0 * sr))
	var ext := b.slice(n - pre)
	ext.append_array(b)
	var w := reverb_wet(ext, sr, feedback, damp)
	for i in n:
		b[i] += w[pre + i] * wet


## Makes noise-like material seamless: `b` must be `n + xfade` samples long; the extra tail is
## cross-faded into the head and the result has exactly `n` samples.
static func loopify(b: PackedFloat32Array, n: int, xfade: int) -> PackedFloat32Array:
	var out := b.slice(0, n)
	for i in xfade:
		var w: float = float(i) / float(xfade)
		out[i] = b[n + i] * (1.0 - w) + b[i] * w
	return out


# ---------------------------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------------------------

## Memoryless soft limiter: unchanged below `knee_db`, then smoothly saturates towards
## `ceiling_db` (never reaches it). Keeps loop seams continuous.
static func soft_limit(b: PackedFloat32Array, ceiling_db: float, knee_db: float) -> void:
	var ceil_lin: float = pow(10.0, ceiling_db / 20.0)
	var knee: float = pow(10.0, knee_db / 20.0)
	var room: float = ceil_lin - knee
	for i in b.size():
		var x: float = b[i]
		var a: float = absf(x)
		if a > knee:
			var y: float = knee + room * tanh((a - knee) / room)
			b[i] = y if x > 0.0 else -y


## Brings the buffer to roughly `target_rms_db` (RMS in dBFS) while never exceeding `ceiling_db`:
## gain, soft-limit, then one corrective pass. Removes DC first.
static func fit_loudness(b: PackedFloat32Array, target_rms_db: float, ceiling_db: float = -1.5, knee_db: float = -9.0) -> void:
	remove_dc(b)
	var r: float = rms(b)
	if r < 1e-9:
		return
	var target: float = pow(10.0, target_rms_db / 20.0)
	scale(b, target / r)
	soft_limit(b, ceiling_db, knee_db)
	var r2: float = rms(b)
	if r2 > 1e-9 and absf(to_db(r2) - target_rms_db) > 0.3:
		scale(b, minf(target / r2, 2.0))
		soft_limit(b, ceiling_db, knee_db)


## Standard SFX finishing: loudness fit (see fit_loudness), 0.5 ms fade in, 12 ms fade out.
static func finish_sfx(b: PackedFloat32Array, sr: int, target_rms_db: float) -> void:
	fit_loudness(b, target_rms_db)
	fade_in(b, int(0.0005 * sr))
	fade_out(b, int(0.012 * sr))


static func to_pcm16(b: PackedFloat32Array) -> PackedByteArray:
	var n: int = b.size()
	var out := PackedByteArray()
	out.resize(n * 2)
	for i in n:
		out.encode_s16(i * 2, clampi(int(roundf(b[i] * 32767.0)), -32768, 32767))
	return out


static func make_stream(pcm: PackedByteArray, sr: int, loop_frames: int = 0) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = sr
	s.stereo = false
	s.data = pcm
	if loop_frames > 0:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = loop_frames
	return s


## Quick numeric report: {peak_db, rms_db, dc, seconds}.
static func stats(b: PackedFloat32Array, sr: int) -> Dictionary:
	return {
		"peak_db": to_db(peak(b)),
		"rms_db": to_db(rms(b)),
		"dc": mean(b),
		"seconds": float(b.size()) / sr,
	}
