# Angel taunts (Ted's wife's wish list, Nov 25): holy trumpets, an ethereal laugh, a choir "aaah",
# a "come here" whistle, plus a giggle, a teasing sing-song and the "Ha-HA!" signature.
# All synthesized here, no samples: female voices are additive formant synthesis (a glottal-ish
# harmonic series shaped by vowel formants, read from small wavetables), with breath and "h" noise
# through a band-pass filter, vibrato and a little pitch wander; trumpets are FM brass; harp and
# bells are decaying sine partials; everything gets a small Freeverb-style reverb tail.
# Each sound is mono 22050 Hz 16-bit, peak-normalised to about -3 dBFS. Callers cache the result.
# Noise comes from a RandomNumberGenerator with a fixed seed per sound, never the global one.
extends RefCounted

const RATE := 22050
const PEAK := 0.708   # -3 dBFS
const TABLE := 1024   # wavetable length

# key -> label shown on screen (the signature isn't in here: it has its own key, "signature")
const TAUNTS := {
	"trumpet": "Holy trumpet",
	"laugh": "Heavenly laugh",
	"choir": "Angel choir",
	"whistle": "Come here~",
	"giggle": "Tee-hee-hee",
	"sing_song": "La-la-la-la-laaa",
}
const SIGNATURE_LABEL := "Ha-HA!"

# Female vowel formants: [centre Hz, bandwidth Hz, gain]
const VOWELS := {
	"a": [[850.0, 90.0, 1.0], [1220.0, 110.0, 0.5], [2810.0, 170.0, 0.25], [3300.0, 250.0, 0.12]],
	"e": [[600.0, 80.0, 1.0], [2000.0, 120.0, 0.4], [2800.0, 170.0, 0.25], [3300.0, 250.0, 0.12]],
	"i": [[330.0, 60.0, 1.0], [2700.0, 140.0, 0.32], [3200.0, 190.0, 0.25], [3800.0, 250.0, 0.1]],
	"o": [[520.0, 80.0, 1.0], [900.0, 100.0, 0.6], [2800.0, 170.0, 0.15], [3300.0, 250.0, 0.08]],
	"u": [[380.0, 70.0, 1.0], [950.0, 100.0, 0.35], [2700.0, 170.0, 0.1], [3300.0, 250.0, 0.05]],
}

const PENTA := [1046.5, 1174.7, 1318.5, 1568.0, 1760.0, 2093.0, 2349.3]   # C6 major pentatonic


static func make(key: String) -> AudioStreamWAV:
	match key:
		"trumpet":
			return _trumpet()
		"laugh":
			return _laugh()
		"choir":
			return _choir()
		"whistle":
			return _whistle_call()
		"giggle":
			return _giggle()
		"sing_song":
			return _sing_song()
		"signature":
			return _signature()
	push_error("angel_taunts: unknown taunt '%s'" % key)
	return _giggle()


# ---------- the taunts ----------

# A short triumphant fanfare: G4-C5-E5 pickups into a held G5 with a C-E-G chord under it, a vibrato
# blooming on the long note, a few glints of bells, in a big hall.
static func _trumpet() -> AudioStreamWAV:
	var buf := _new_buf(2.2)
	var rng := _rng(1101)
	_brass(buf, 0.0, 0.12, 392.0, 0.9)
	_brass(buf, 0.14, 0.12, 523.25, 0.95)
	_brass(buf, 0.28, 0.12, 659.26, 1.0)
	_brass(buf, 0.42, 0.95, 783.99, 1.0, 0.25)
	_brass(buf, 0.42, 0.95, 659.26, 0.5, 0.3)
	_brass(buf, 0.42, 0.95, 523.25, 0.42, 0.35)
	_sparkle(buf, rng, 0.5, 0.8, 6, 0.1)
	_reverb(buf, 0.5, 0.84, 0.3)
	return _finish(buf)


# An airy, sparkly "ha-ha-ha-ha-haaa": falling breathy syllables, an echo, bells and lots of hall.
static func _laugh() -> AudioStreamWAV:
	var buf := _new_buf(2.4)
	var rng := _rng(2202)
	var tops := [900.0, 850.0, 810.0, 770.0]
	var amps := [0.85, 1.0, 0.9, 0.8]
	for k in tops.size():
		var f: float = tops[k]
		_sing(buf, rng, {"at": k * 0.18, "h": 0.04, "dur": 0.11, "f0": f * 1.04, "f1": f * 0.9,
				"va": "a", "vb": "e", "breath": 0.45, "tilt": 1.4, "amp": amps[k], "attack": 0.015})
	_sing(buf, rng, {"at": 0.74, "h": 0.04, "dur": 0.42, "f0": 790.0, "f1": 560.0, "curve": 1.6,
			"va": "a", "breath": 0.45, "tilt": 1.4, "amp": 0.85, "vib": 0.02, "release": 0.18})
	_echo(buf, 0.21, 0.3)
	_sparkle(buf, rng, 0.1, 1.2, 9, 0.09)
	_reverb(buf, 0.7, 0.86, 0.25)
	return _finish(buf)


# A short choir "aaaah" swelling in and out: G4 C5 E5 G5, two slightly detuned singers per note,
# each with her own vibrato, ending on a soft bell.
static func _choir() -> AudioStreamWAV:
	var buf := _new_buf(2.5)
	var rng := _rng(3303)
	var notes := [392.0, 523.25, 659.26, 783.99]
	var amps := [0.8, 0.9, 0.85, 0.7]
	for k in notes.size():
		for c in 2:
			var cents := -7.0 if c == 0 else 7.0
			_sing(buf, rng, {"at": rng.randf() * 0.05, "dur": 1.7, "f0": notes[k],
					"f1": notes[k] * 1.004, "detune": pow(2.0, cents / 1200.0), "va": "a", "vb": "o",
					"breath": 0.14, "tilt": 1.5, "amp": amps[k], "vib": 0.011,
					"vib_rate": 4.8 + rng.randf() * 1.2, "vib_phase": rng.randf() * TAU,
					"attack": 0.5, "release": 0.6})
	_bell(buf, 0.62, 2093.0, 0.12, 4.0)
	_reverb(buf, 0.55, 0.85, 0.3)
	return _finish(buf)


# A two-note "come here!" whistle: a quick scoop up to A6, then a slide down to about E6.
static func _whistle_call() -> AudioStreamWAV:
	var buf := _new_buf(1.5)
	var rng := _rng(4404)
	_whistle(buf, rng, 0.0, 0.26, 1250.0, 1760.0, 1.0, 0.35)
	_whistle(buf, rng, 0.34, 0.5, 1760.0, 1300.0, 1.0, 2.0)
	_reverb(buf, 0.28, 0.8, 0.35)
	return _finish(buf)


# "Hee-hee-hee-hee": quick bright breathy syllables, each falling a little.
static func _giggle() -> AudioStreamWAV:
	var buf := _new_buf(1.4)
	var rng := _rng(5505)
	var tops := [1060.0, 1010.0, 970.0, 920.0]
	var amps := [0.9, 1.0, 0.9, 0.8]
	for k in tops.size():
		var f: float = tops[k]
		_sing(buf, rng, {"at": k * 0.14, "h": 0.025, "dur": 0.08, "f0": f * 1.04, "f1": f * 0.93,
				"va": "i", "vb": "e", "breath": 0.3, "tilt": 1.2, "amp": amps[k], "attack": 0.01,
				"release": 0.035})
	_sing(buf, rng, {"at": 0.56, "h": 0.025, "dur": 0.2, "f0": 950.0, "f1": 780.0, "curve": 1.5,
			"va": "i", "vb": "e", "breath": 0.3, "tilt": 1.2, "amp": 0.75, "release": 0.08})
	_sparkle(buf, rng, 0.15, 0.6, 4, 0.06)
	_reverb(buf, 0.35, 0.82, 0.3)
	return _finish(buf)


# The teasing "la-la-la-la-laaa" (G5 E5 A5 G5 E5), sung sweetly, with a harp plucking along.
static func _sing_song() -> AudioStreamWAV:
	var buf := _new_buf(2.3)
	var rng := _rng(6606)
	var notes := [783.99, 659.26, 880.0, 783.99, 659.26]
	var durs := [0.22, 0.22, 0.16, 0.2, 0.5]
	var at := 0.0
	for k in notes.size():
		var last := k == notes.size() - 1
		_sing(buf, rng, {"at": at, "dur": durs[k], "f0": notes[k], "f1": notes[k] * (0.985 if last else 1.0),
				"va": "u", "vb": "a", "vt": 0.06, "breath": 0.12, "tilt": 1.2, "amp": 1.0,
				"vib": 0.025 if last else 0.01, "attack": 0.03, "release": 0.15 if last else 0.05})
		_pluck(buf, at, notes[k] * 0.5, 0.3)
		at += durs[k] + 0.02
	_reverb(buf, 0.4, 0.83, 0.3)
	return _finish(buf)


# The signature: a confident "ha-HA!" and a harp glissando up into a sparkle.
static func _signature() -> AudioStreamWAV:
	var buf := _new_buf(2.0)
	var rng := _rng(7707)
	_sing(buf, rng, {"at": 0.0, "h": 0.045, "dur": 0.12, "f0": 620.0, "f1": 680.0, "va": "a",
			"breath": 0.25, "tilt": 1.1, "amp": 0.7, "attack": 0.015})
	_sing(buf, rng, {"at": 0.24, "h": 0.03, "dur": 0.32, "f0": 960.0, "f1": 820.0, "curve": 1.3,
			"va": "a", "breath": 0.2, "tilt": 0.95, "amp": 1.0, "vib": 0.015, "release": 0.1})
	var gliss := [523.25, 587.33, 659.26, 783.99, 880.0, 1046.5, 1174.7, 1318.5]
	for k in gliss.size():
		_pluck(buf, 0.5 + k * 0.045, gliss[k], 0.28)
	_bell(buf, 0.86, 2093.0, 0.16, 3.5)
	_sparkle(buf, rng, 0.88, 0.35, 4, 0.08)
	_reverb(buf, 0.4, 0.83, 0.3)
	return _finish(buf)


# ---------- instruments ----------

# One sung syllable added into buf. p keys (defaults): at (0) start s, h (0) "h" breath lead-in s,
# dur voiced s, f0 / f1 (f0) start and end pitch Hz, curve (1) glide shape, detune (1) pitch factor,
# va / vb (va) start and end vowel, vt (dur) vowel-change time, amp (1), breath (0.15) breathiness,
# tilt (1.1) spectral tilt (higher = softer), vib (0.012) vibrato depth, vib_rate (5.6), vib_phase (0),
# attack (0.025), release (0.06).
static func _sing(buf: PackedFloat32Array, rng: RandomNumberGenerator, p: Dictionary) -> void:
	var at: float = p.get("at", 0.0)
	var h: float = p.get("h", 0.0)
	var dur: float = p["dur"]
	var det: float = p.get("detune", 1.0)
	var f0a: float = p["f0"] * det
	var f0b: float = p.get("f1", p["f0"]) * det
	var curve: float = p.get("curve", 1.0)
	var va: String = p.get("va", "a")
	var vb: String = p.get("vb", va)
	var vt: float = p.get("vt", dur)
	var amp: float = p.get("amp", 1.0)
	var breath: float = p.get("breath", 0.15)
	var tilt: float = p.get("tilt", 1.1)
	var vib: float = p.get("vib", 0.012)
	var vib_rate: float = p.get("vib_rate", 5.6)
	var vib_phase: float = p.get("vib_phase", 0.0)
	var attack: float = p.get("attack", 0.025)
	var release: float = p.get("release", 0.06)

	var fmax := maxf(f0a, f0b) * (1.0 + vib + 0.02)
	var fmid := sqrt(f0a * f0b)
	var ta := _vowel_table(va, fmid, fmax, tilt)
	var tb := ta if vb == va else _vowel_table(vb, fmid, fmax, tilt)
	var fa: Array = VOWELS[va]
	var fb: Array = VOWELS[vb]
	var c0: float = (fa[0][0] + fa[1][0]) * 0.5   # where the breath noise sits (between F1 and F2)
	var c1: float = (fb[0][0] + fb[1][0]) * 0.5
	var start := int(at * RATE)
	var n := int((h + dur) * RATE)
	var ph := rng.randf()
	var low := 0.0
	var band := 0.0
	var wander := 0.0
	for j in n:
		var idx := start + j
		if idx >= buf.size():
			break
		var t := float(j) / RATE
		var tv := t - h                      # time since the voice started
		var mixv := smoothstep(0.0, vt, maxf(tv, 0.0))
		# white noise through a band-pass: the "h" and the breathiness
		var fc := lerpf(c0, c1, mixv)
		var fcoef := 2.0 * sin(PI * fc / RATE)
		low += fcoef * band
		var high := rng.randf_range(-1.0, 1.0) - low - band * 1.2
		band += fcoef * high
		wander = lerpf(wander, rng.randf_range(-1.0, 1.0), 0.004)
		var hamp := 0.0
		if h > 0.0:
			hamp = smoothstep(0.0, h * 0.7, t) * (1.0 - smoothstep(h, h + 0.05, t))
		var s := band * hamp * amp * 1.8
		if tv >= 0.0 and tv < dur:
			var u := tv / dur
			var env := sin(minf(tv / attack, 1.0) * PI * 0.5) * sin(minf((dur - tv) / release, 1.0) * PI * 0.5) * amp
			var f := f0a * pow(f0b / f0a, pow(u, curve))
			f *= 1.0 + vib * smoothstep(0.0, 0.25, tv) * sin(TAU * vib_rate * tv + vib_phase) + wander * 0.006
			ph += f / RATE
			ph -= floorf(ph)
			var v := lerpf(_read(ta, ph), _read(tb, ph), mixv)
			s += v * env * (1.0 + wander * 0.08) + band * breath * env * (0.5 + 0.5 * absf(v)) * 2.0
		buf[idx] += s


# One period of a vowel at pitch f0: harmonics falling off by 1/k^tilt, shaped by the vowel's formant
# peaks (widened for high voices so sparse harmonics still catch them). Harmonics stop below Nyquist
# for the highest pitch it will be played at.
static func _vowel_table(vowel: String, f0: float, fmax: float, tilt: float) -> PackedFloat32Array:
	var forms: Array = VOWELS[vowel]
	var kmax := clampi(int(9500.0 / fmax), 1, 40)
	var amps := PackedFloat32Array()
	for k in range(1, kmax + 1):
		var f := f0 * k
		var g := 0.0
		for fm in forms:
			var bw: float = fm[1] + f0 * 0.5
			var d: float = (f - fm[0]) / bw
			g += fm[2] / (1.0 + d * d)
		amps.append((g + 0.02) / pow(k, tilt))
	var tab := PackedFloat32Array()
	tab.resize(TABLE + 1)
	var peak := 0.0
	for i in TABLE:
		var x := TAU * i / TABLE
		var s := 0.0
		for k in amps.size():
			s += amps[k] * sin(x * (k + 1))
		tab[i] = s
		peak = maxf(peak, absf(s))
	for i in TABLE:
		tab[i] /= peak
	tab[TABLE] = tab[0]
	return tab


static func _read(tab: PackedFloat32Array, ph: float) -> float:
	var x := ph * TABLE
	var i := int(x)
	return lerpf(tab[i], tab[i + 1], x - i)


# FM brass (carrier = modulator): the brightness follows the loudness like a real horn, a small pitch
# scoop and a breathy "t" at the start, and vibrato that blooms after vib_delay on long notes.
static func _brass(buf: PackedFloat32Array, at: float, dur: float, hz: float, amp: float, vib_delay := 0.3) -> void:
	var start := int(at * RATE)
	var n := int(dur * RATE)
	var p1 := 0.0
	var p2 := 0.0
	var tick := 0.0
	var rng := _rng(int(hz * 10.0) + start)
	for j in n:
		var idx := start + j
		if idx >= buf.size():
			break
		var t := float(j) / RATE
		var env := sin(minf(t / 0.035, 1.0) * PI * 0.5) * (0.8 + 0.25 * exp(-t * 14.0))
		env *= sin(minf((dur - t) / 0.07, 1.0) * PI * 0.5)
		var index := 0.5 + 2.6 * pow(env, 1.5)
		var vibr := 0.008 * smoothstep(vib_delay, vib_delay + 0.25, t) * sin(TAU * 5.3 * t)
		var f := hz * (1.0 - 0.03 * exp(-t * 40.0)) * (1.0 + vibr)
		p1 += TAU * f / RATE
		p2 += TAU * f * 1.003 / RATE
		var s := sin(p1 + index * sin(p1)) + sin(p2 + index * 0.9 * sin(p2))
		tick = lerpf(tick, rng.randf_range(-1.0, 1.0), 0.3)
		buf[idx] += (s * 0.5 * env + tick * 0.25 * exp(-t * 60.0)) * amp


# A whistled note gliding from fa to fb (curve shapes the glide): a near-pure tone, a breathy
# narrow band of noise around it, a puff of air at the start, a slight wobble.
static func _whistle(buf: PackedFloat32Array, rng: RandomNumberGenerator, at: float, dur: float,
		fa: float, fb: float, amp: float, curve: float) -> void:
	var start := int(at * RATE)
	var n := int(dur * RATE)
	var ph := 0.0
	var low := 0.0
	var band := 0.0
	var air := 0.0
	for j in n:
		var idx := start + j
		if idx >= buf.size():
			break
		var t := float(j) / RATE
		var u := t / dur
		var f := fa * pow(fb / fa, pow(u, curve))
		f *= 1.0 + 0.006 * smoothstep(0.05, 0.2, t) * sin(TAU * 6.0 * t)
		ph += f / RATE
		ph -= floorf(ph)
		var white := rng.randf_range(-1.0, 1.0)
		var fcoef := 2.0 * sin(PI * f / RATE)
		low += fcoef * band
		var high := white - low - band * 0.3
		band += fcoef * high
		air = lerpf(air, white, 0.25)
		var env := sin(minf(t / 0.03, 1.0) * PI * 0.5) * sin(minf((dur - t) / 0.07, 1.0) * PI * 0.5)
		var tone := sin(TAU * ph) + 0.04 * sin(2.0 * TAU * ph)
		buf[idx] += (tone * 0.9 + band * 0.12 + air * 0.3 * exp(-t * 25.0)) * env * amp


# A harp-ish pluck: a few harmonics, higher ones dying faster.
static func _pluck(buf: PackedFloat32Array, at: float, hz: float, amp: float) -> void:
	var start := int(at * RATE)
	var n := int(1.2 * RATE)
	var kmax := mini(6, int(9000.0 / hz))
	for j in n:
		var idx := start + j
		if idx >= buf.size():
			break
		var t := float(j) / RATE
		var s := 0.0
		for k in range(1, kmax + 1):
			s += sin(TAU * hz * k * t) / pow(k, 1.4) * exp(-t * (2.5 + 1.8 * k))
		buf[idx] += s * minf(t / 0.003, 1.0) * amp


# A small glassy bell: inharmonic partials, quick attack, exponential decay.
static func _bell(buf: PackedFloat32Array, at: float, hz: float, amp: float, decay: float) -> void:
	var start := int(at * RATE)
	var n := int(minf(6.0 / decay, 1.5) * RATE)
	var parts := [[1.0, 1.0, 1.0], [2.0, 0.3, 1.6], [2.76, 0.22, 2.2], [5.4, 0.08, 3.5]]
	for j in n:
		var idx := start + j
		if idx >= buf.size():
			break
		var t := float(j) / RATE
		var s := 0.0
		for pt in parts:
			var f: float = hz * pt[0]
			if f < 10000.0:
				s += sin(TAU * f * t) * pt[1] * exp(-t * decay * pt[2])
		buf[idx] += s * minf(t / 0.002, 1.0) * amp


# A scatter of tiny high bells from the pentatonic scale.
static func _sparkle(buf: PackedFloat32Array, rng: RandomNumberGenerator, at: float, span: float,
		count: int, amp: float) -> void:
	for k in count:
		var hz: float = PENTA[rng.randi_range(0, PENTA.size() - 1)]
		_bell(buf, at + span * (k + rng.randf() * 0.8) / count, hz, amp * (0.6 + 0.4 * rng.randf()), 6.0)


# ---------- effects + output ----------

# Feedback echo.
static func _echo(buf: PackedFloat32Array, delay: float, gain: float) -> void:
	var d := int(delay * RATE)
	for i in range(d, buf.size()):
		buf[i] += buf[i - d] * gain


# A small mono Freeverb: six damped comb filters into four all-passes, mixed back in at `wet`.
# room is the comb feedback (0.84 is roughly a one-second tail).
static func _reverb(buf: PackedFloat32Array, wet: float, room: float, damp: float) -> void:
	var combs := PackedInt32Array([557, 593, 641, 677, 709, 743])
	var aps := PackedInt32Array([278, 220, 170, 112])
	var coff := PackedInt32Array()
	var aoff := PackedInt32Array()
	var total := 0
	for d in combs:
		coff.append(total)
		total += d
	var lines := PackedFloat32Array()
	lines.resize(total)
	total = 0
	for d in aps:
		aoff.append(total)
		total += d
	var alines := PackedFloat32Array()
	alines.resize(total)
	var cpos := PackedInt32Array([0, 0, 0, 0, 0, 0])
	var apos := PackedInt32Array([0, 0, 0, 0])
	var filt := PackedFloat32Array([0, 0, 0, 0, 0, 0])
	var pre := int(0.02 * RATE)
	var n := buf.size()
	var rev := PackedFloat32Array()
	rev.resize(n)
	for i in n:
		var x := buf[i - pre] * 0.1 if i >= pre else 0.0
		var sum := 0.0
		for k in 6:
			var q := coff[k] + cpos[k]
			var y := lines[q]
			filt[k] = y * (1.0 - damp) + filt[k] * damp
			lines[q] = x + filt[k] * room
			cpos[k] = (cpos[k] + 1) % combs[k]
			sum += y
		for k in 4:
			var q := aoff[k] + apos[k]
			var bo := alines[q]
			alines[q] = sum + bo * 0.5
			sum = bo - sum
			apos[k] = (apos[k] + 1) % aps[k]
		rev[i] = sum
	for i in n:
		buf[i] += rev[i] * wet


static func _new_buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	b.fill(0.0)
	return b


static func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


# DC blocker, click-free fades at both ends, peak-normalise to -3 dBFS, 16-bit mono WAV.
static func _finish(buf: PackedFloat32Array) -> AudioStreamWAV:
	var n := buf.size()
	var x1 := 0.0
	var y1 := 0.0
	for i in n:
		var x := buf[i]
		var y := x - x1 + 0.997 * y1
		x1 = x
		y1 = y
		buf[i] = y
	var fin := int(0.004 * RATE)
	for i in fin:
		buf[i] *= float(i) / fin
	var fout := mini(int(0.3 * RATE), n / 4)
	for i in fout:
		buf[n - 1 - i] *= sin(0.5 * PI * float(i) / fout)
	var peak := 0.0001
	for i in n:
		peak = maxf(peak, absf(buf[i]))
	var gain := PEAK / peak
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(roundf(clampf(buf[i] * gain, -1.0, 1.0) * 32767.0)))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
