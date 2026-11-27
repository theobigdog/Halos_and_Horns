# The thrown blessings' sounds, one set per kind (blessings.gd KINDS, plus "book" for Holy Scripture and
# "vacuum" for the Vacuum Orb). Synthesized in code like everything else (sfx.gd); each made once and
# cached. Each sound uses its own RandomNumberGenerator with a fixed seed, never the global randf().
#   throw(kind):  a short whoosh with character as it leaves the angel's hand (~0.25-0.45 s).
#   impact(kind): where it lands on something that isn't a demon (~0.2-0.55 s).
# Players throw constantly, so everything is short, soft-edged and mostly below ~3 kHz (the SFX bus
# low-passes at 3.2 kHz anyway); the character comes from shape, pitch movement and texture, not loudness.
# Each sound is built from a few small layers (decaying partials, band-passed noise, bubbles, a sung
# chord through vowel formants), then peak-normalized so the kinds sit at the same level.
extends RefCounted

const Sfx = preload("res://scripts/sfx.gd")
const RATE := Sfx.RATE

# Loudness targets: the loudest 50 ms of each sound (RMS) is set to these. For scale, Sfx.hit_sound()
# measures about 0.032; throws play another -4 dB down in main.gd, so they sit a little under it.
const THROW_LOUD := 0.04
const IMPACT_LOUD := 0.042
const MAX_PEAK := 0.25

static var _cache := {}


# Thrown (plays from the thrower: main.gd, on the player's "threw" signal).
static func throw(kind: String) -> AudioStream:
	var key := "throw_" + kind
	if not _cache.has(key):
		_cache[key] = _make_throw(kind)
	return _cache[key]


# It hit something that isn't a demon (a wall, the ground, a prop): plays where it landed (projectile.gd).
static func impact(kind: String) -> AudioStream:
	var key := "impact_" + kind
	if not _cache.has(key):
		_cache[key] = _make_impact(kind)
	return _cache[key]


static func _make_throw(kind: String) -> AudioStreamWAV:
	match kind:
		"holy_light":
			return _light_throw()
		"blessed_water":
			return _water_throw()
		"halo_ring":
			return _halo_throw()
		"feather":
			return _feather_throw()
		"choir":
			return _choir_throw()
		"book":
			return _book_throw()
		"vacuum":
			return _vacuum_throw()
	return _light_throw()


static func _make_impact(kind: String) -> AudioStreamWAV:
	match kind:
		"holy_light":
			return _light_impact()
		"blessed_water":
			return _water_impact()
		"halo_ring":
			return _halo_impact()
		"feather":
			return _feather_impact()
		"choir":
			return _choir_impact()
		"book":
			return _book_impact()
		"vacuum":
			return _vacuum_impact()
	return _light_impact()


# ---------- building blocks ----------

static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(RATE * seconds))
	return b


# Chamberlin state-variable filter coefficient (kept well below its stability limit).
static func _svf_f(hz: float) -> float:
	return 2.0 * sin(PI * clampf(hz, 20.0, 3600.0) / RATE)


# A decaying sine added at `start` s. glide: the pitch starts at hz and slides towards hz * glide at
# `glide_rate` (1/s). trem_hz/trem_depth: a loudness wobble whose speed doubles over the note (a coin
# or ring settling). Stops once it has died away.
static func _partial(buf: PackedFloat32Array, start: float, hz: float, amp: float, decay: float,
		attack := 0.002, glide := 1.0, glide_rate := 0.0, trem_hz := 0.0, trem_depth := 0.0,
		phase := 0.0) -> void:
	var n := buf.size()
	var i0 := int(start * RATE)
	var len_n := mini(n - i0, int(RATE * 7.0 / maxf(decay, 1.0)) + int(attack * RATE))
	var ph := phase
	var tph := 0.0
	for j in len_n:
		var t := float(j) / RATE
		var f := hz * lerpf(glide, 1.0, exp(-t * glide_rate))
		ph += TAU * f / RATE
		var env := sin(minf(t / attack, 1.0) * PI * 0.5) * exp(-t * decay)
		if trem_depth > 0.0:
			tph += TAU * trem_hz * (1.0 + float(j) / len_n) / RATE
			env *= 1.0 - trem_depth * (0.5 - 0.5 * cos(tph))   # starts at full loudness
		buf[i0 + j] += sin(ph) * amp * env


# Band-passed (mode 0) or low-passed (mode 1) noise from `start` for `dur` s. The centre sweeps from f0 to
# f1 (exponentially); the loudness eases in over `attack` s and fades out as (1 - u)^power. flutter_hz /
# flutter_depth chop it into soft pulses (wing beats, a spinning ring). The output is roughly
# level-matched across centre frequencies, so `amp` means about the same thing for every band.
static func _noise(buf: PackedFloat32Array, rng: RandomNumberGenerator, start: float, dur: float,
		f0: float, f1: float, q: float, amp: float, attack: float, power: float, mode := 0,
		flutter_hz := 0.0, flutter_depth := 0.0, flutter_hz_end := -1.0) -> void:
	var n := buf.size()
	var i0 := int(start * RATE)
	var len_n := mini(n - i0, int(dur * RATE))
	var lo := 0.0
	var band := 0.0
	var fph := 0.0
	var fl_end := flutter_hz if flutter_hz_end < 0.0 else flutter_hz_end
	for j in len_n:
		var t := float(j) / RATE
		var u := float(j) / len_n
		var fc := f0 * pow(f1 / f0, u)
		var f := _svf_f(fc)
		var hi := rng.randf_range(-1.0, 1.0) - lo - q * band
		band += f * hi
		lo += f * band
		var out: float
		if mode == 0:
			out = band * q * sqrt(RATE * 0.5 / maxf(fc * q, 60.0))
		else:
			out = lo * sqrt(RATE * 0.5 / fc)
		var env := sin(minf(t / attack, 1.0) * PI * 0.5) * pow(1.0 - u, power)
		if flutter_depth > 0.0:
			fph += TAU * lerpf(flutter_hz, fl_end, u) / RATE
			var p := 0.5 + 0.5 * sin(fph)
			env *= 1.0 - flutter_depth + flutter_depth * p * p
		buf[i0 + j] += out * amp * 0.35 * env


# A water bubble "bloop": a sine whose pitch rises quickly as it dies (that rise is what reads as liquid).
static func _bubble(buf: PackedFloat32Array, start: float, hz: float, amp: float, dur: float, rise := 1.6) -> void:
	var n := buf.size()
	var i0 := int(start * RATE)
	var len_n := mini(n - i0, int(dur * RATE))
	var ph := 0.0
	for j in len_n:
		var t := float(j) / RATE
		var u := float(j) / len_n
		ph += TAU * hz * (1.0 + (rise - 1.0) * u * u) / RATE
		var env := sin(minf(t / 0.003, 1.0) * PI * 0.5) * pow(1.0 - u, 1.5)
		buf[i0 + j] += sin(ph) * amp * env


# A tiny crisp tick (paper edge, droplet, spark): a few ms of high-passed noise ringing at `hz`.
static func _tick(buf: PackedFloat32Array, rng: RandomNumberGenerator, start: float, hz: float, amp: float,
		decay := 400.0, ring := 0.5) -> void:
	var n := buf.size()
	var i0 := int(start * RATE)
	var len_n := mini(n - i0, int(RATE * 6.0 / decay))
	var prev := 0.0
	for j in len_n:
		var t := float(j) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		var hp := w - prev
		prev = w
		buf[i0 + j] += amp * exp(-t * decay) * (hp * 0.5 + ring * sin(TAU * hz * t))


# A small choir singing `notes` (Hz) on "ah": two slightly detuned band-limited saw voices per note with
# vibrato, through vowel formants. Each note scoops up from `swoop` semitones below over `swoop_t` s.
static func _choir(buf: PackedFloat32Array, rng: RandomNumberGenerator, start: float, dur: float,
		notes: Array, amp: float, attack: float, power: float, swoop := 0.0, swoop_t := 0.08,
		formants := [[780.0, 1.0, 0.12], [1180.0, 0.6, 0.1], [2700.0, 0.2, 0.08]]) -> void:
	var n := buf.size()
	var i0 := int(start * RATE)
	var len_n := mini(n - i0, int(dur * RATE))
	var voices := notes.size() * 2
	var phases := PackedFloat32Array()
	var detune := PackedFloat32Array()
	for v in voices:
		phases.append(rng.randf())
		detune.append(1.0 + (0.004 if v % 2 == 0 else -0.004) + rng.randf_range(-0.002, 0.002))
	var fl := PackedFloat32Array()
	var fb := PackedFloat32Array()
	for k in formants.size():
		fl.append(0.0)
		fb.append(0.0)
	var breath := 0.0
	for j in len_n:
		var t := float(j) / RATE
		var u := float(j) / len_n
		var bend := pow(2.0, -swoop * (1.0 - smoothstep(0.0, swoop_t, t)) / 12.0)
		var vib := 1.0 + 0.012 * sin(TAU * 5.8 * t) * minf(t / 0.1, 1.0)
		var src := 0.0
		for v in voices:
			var dt: float = notes[v / 2] * bend * vib * detune[v] / RATE
			var p := phases[v] + dt
			p -= floorf(p)
			phases[v] = p
			# polyBLEP saw: bright enough for formants to shape, without aliasing hash
			var s := 2.0 * p - 1.0
			if p < dt:
				var x := p / dt
				s -= x + x - x * x - 1.0
			elif p > 1.0 - dt:
				var x := (p - 1.0) / dt
				s -= x * x + x + x + 1.0
			src += s
		src /= voices
		breath = lerpf(breath, rng.randf_range(-1.0, 1.0), 0.3)
		src += breath * 0.08
		var out := 0.0
		for k in formants.size():
			var q: float = formants[k][2] * 2.0
			var f := _svf_f(formants[k][0])
			var hi: float = src - fl[k] - q * fb[k]
			fb[k] += f * hi
			fl[k] += f * fb[k]
			out += fb[k] * formants[k][1]
		var env := sin(minf(t / attack, 1.0) * PI * 0.5) * pow(1.0 - u, power)
		buf[i0 + j] += out * amp * env


# To 16-bit at loudness `loud` (the RMS of its loudest 50 ms, bass-reduced, so short clicky peaks don't decide how
# loud a sound is), never peaking above MAX_PEAK, with a short fade at the very end (always ends silent).
static func _to_wav(buf: PackedFloat32Array, loud: float) -> AudioStreamWAV:
	var n := buf.size()
	# a gentle two-pole roll-off above ~4 kHz first: keeps noise layers from turning to hiss
	var a := 1.0 - exp(-TAU * 4000.0 / RATE)
	var l1 := 0.0
	var l2 := 0.0
	for i in n:
		l1 += (buf[i] - l1) * a
		l2 += (l1 - l2) * a
		buf[i] = l2
	var top := 0.0001
	var win := 0.0
	var best := 0.0
	var wn := int(RATE * 0.05)
	# loudness is judged on a high-passed copy (~250 Hz): deep thuds sound quieter than their RMS says
	var hp := PackedFloat32Array()
	hp.resize(n)
	var ah := 1.0 - exp(-TAU * 250.0 / RATE)
	var low := 0.0
	for i in n:
		top = maxf(top, absf(buf[i]))
		low += (buf[i] - low) * ah
		hp[i] = buf[i] - low
		win += hp[i] * hp[i]
		if i >= wn:
			win -= hp[i - wn] * hp[i - wn]
		best = maxf(best, win)
	var gain := minf(loud / maxf(sqrt(best / wn), 0.00001), MAX_PEAK / top)
	var tail := mini(int(RATE * 0.012), n)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var s := buf[i] * gain
		if i >= n - tail:
			s *= float(n - 1 - i) / tail
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav


static func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


# ---------- Holy Light: a radiant star ----------

# A bright shimmering "zing": a rising glassy sweep with a fast shimmer, chimes ringing out of it, over
# an airy rush.
static func _light_throw() -> AudioStreamWAV:
	var b := _buf(0.34)
	var rng := _rng(7101)
	# the zing: a sweep up an octave, shimmering (fast tremolo) as it goes
	_partial(b, 0.0, 880.0, 0.5, 7.0, 0.012, 2.0, 6.0, 32.0, 0.45)
	_partial(b, 0.0, 1320.0, 0.25, 9.0, 0.02, 2.0, 6.0, 41.0, 0.5)
	# chimes ringing out of the sweep, rising
	_partial(b, 0.03, 1568.0, 0.32, 11.0, 0.004)
	_partial(b, 0.07, 1976.0, 0.26, 12.0, 0.004)
	_partial(b, 0.11, 2637.0, 0.18, 14.0, 0.004)
	# the rush of air, brightening as it flies
	_noise(b, rng, 0.0, 0.34, 1200.0, 2800.0, 0.7, 0.55, 0.05, 1.8)
	return _to_wav(b, THROW_LOUD)


# A crisp sparkle burst: a bright snap, a scatter of tiny high tinkles and a soft glowing "pff".
static func _light_impact() -> AudioStreamWAV:
	var b := _buf(0.4)
	var rng := _rng(7102)
	_tick(b, rng, 0.0, 2400.0, 0.9, 260.0, 0.4)
	_noise(b, rng, 0.0, 0.12, 2600.0, 1800.0, 0.8, 0.5, 0.002, 2.5)
	_noise(b, rng, 0.0, 0.2, 700.0, 500.0, 1.0, 0.35, 0.004, 2.0)
	var scale := [1568.0, 1760.0, 1976.0, 2349.0, 2637.0, 2960.0, 3136.0]   # G major-ish sparkle
	for k in 9:
		var at := 0.004 + 0.16 * pow(rng.randf(), 1.4)
		var hz: float = scale[rng.randi_range(0, scale.size() - 1)]
		_partial(b, at, hz, rng.randf_range(0.18, 0.32) * exp(-at * 6.0), rng.randf_range(16.0, 26.0), 0.002)
	return _to_wav(b, IMPACT_LOUD)


# ---------- Blessed Water: a wobbling droplet ----------

# A liquid swoosh with a "bloop" as it leaves the hand and a smaller one trailing.
static func _water_throw() -> AudioStreamWAV:
	var b := _buf(0.34)
	var rng := _rng(7201)
	_noise(b, rng, 0.0, 0.34, 450.0, 1300.0, 0.9, 0.7, 0.06, 1.6, 0, 11.0, 0.35)
	_bubble(b, 0.0, 330.0, 0.75, 0.09, 2.6)
	_bubble(b, 0.1, 520.0, 0.4, 0.06, 2.2)
	_bubble(b, 0.17, 700.0, 0.22, 0.05, 2.0)
	return _to_wav(b, THROW_LOUD)


# A splash: a wet slap, a spray of noise, and droplets plinking down around it.
static func _water_impact() -> AudioStreamWAV:
	var b := _buf(0.48)
	var rng := _rng(7202)
	_partial(b, 0.0, 170.0, 0.6, 22.0, 0.002, 0.6, 30.0)   # the slap's body
	_noise(b, rng, 0.0, 0.32, 1900.0, 900.0, 1.1, 1.0, 0.003, 2.4)   # the spray
	_noise(b, rng, 0.0, 0.12, 600.0, 400.0, 1.2, 0.6, 0.002, 2.0)
	for k in 10:
		var at := 0.02 + 0.36 * pow(rng.randf(), 1.3)
		_bubble(b, at, rng.randf_range(650.0, 1300.0), rng.randf_range(0.15, 0.35) * exp(-at * 4.0),
				rng.randf_range(0.025, 0.05), rng.randf_range(1.5, 2.3))
	return _to_wav(b, IMPACT_LOUD)


# ---------- Halo Ring: a spinning gold ring ----------

# Metallic ring partials (a thin ring's inharmonic modes) whirring as it spins, a little "ting" up front.
const RING := [[1.0, 1.0], [2.32, 0.55], [4.25, 0.3], [6.63, 0.14]]


# (Wife's notes, Nov 26: "make it a more ethereal sound".) No metal ting any more: a soft, glowing chord
# that swells in and floats upward, doubled a few Hz off so it shimmers like a choir, with slow sparkles
# above it and a breath of air.
static func _halo_throw() -> AudioStreamWAV:
	var b := _buf(0.62)
	var rng := _rng(7301)
	var base := 660.0
	for p in [[1.0, 0.36], [1.5, 0.26], [2.0, 0.2], [3.0, 0.07]]:
		_partial(b, 0.0, base * p[0], p[1], 3.2, 0.07, 1.05, 2.5, 6.5, 0.25)
		_partial(b, 0.0, base * p[0] + 2.2 * p[0], p[1] * 0.7, 3.0, 0.09, 1.05, 2.5, 5.0, 0.3, rng.randf() * TAU)
	# sparkles high up, fading in a little later
	for k in 3:
		_partial(b, 0.06 + 0.07 * k, [1760.0, 1976.0, 2349.0][k], 0.06, 7.0, 0.03, 1.02, 4.0, 11.0, 0.5)
	# a soft breath of air
	_noise(b, rng, 0.0, 0.55, 1300.0, 2200.0, 0.6, 0.3, 0.09, 1.6, 0)
	return _to_wav(b, THROW_LOUD)


# A ringing metallic clang/ting that wobbles as the ring settles (the wobble speeds up, like a dropped coin).
static func _halo_impact() -> AudioStreamWAV:
	var b := _buf(0.58)
	var rng := _rng(7302)
	_tick(b, rng, 0.0, 2200.0, 0.8, 500.0, 0.3)   # the strike
	var base := 560.0
	for p in RING:
		var d: float = 3.5 + 3.5 * p[0]
		_partial(b, 0.0, base * p[0], 0.45 * p[1], d, 0.0015, 1.0, 0.0, 8.0, 0.7, rng.randf() * TAU)
		# a twin a few Hz off: the beating shimmer of real metal
		_partial(b, 0.0, base * p[0] + 3.0 + p[0], 0.25 * p[1], d * 1.2, 0.0015, 1.0, 0.0, 8.0, 0.5, rng.randf() * TAU)
	_noise(b, rng, 0.0, 0.06, 2400.0, 1600.0, 1.0, 0.4, 0.001, 2.0)
	return _to_wav(b, IMPACT_LOUD)


# ---------- Feather: a fluttering feather ----------

# A soft fluttering whiff: breathy noise beating like little wings, with the faintest airy tone.
static func _feather_throw() -> AudioStreamWAV:
	var b := _buf(0.32)
	var rng := _rng(7401)
	_noise(b, rng, 0.0, 0.32, 1300.0, 750.0, 0.9, 0.9, 0.04, 1.3, 0, 24.0, 0.85, 15.0)
	_noise(b, rng, 0.0, 0.25, 400.0, 300.0, 1.0, 0.3, 0.03, 1.5, 1)
	_partial(b, 0.0, 1046.0, 0.05, 8.0, 0.04, 0.9, 6.0)
	return _to_wav(b, THROW_LOUD * 0.85)


# A soft puff as it lands, with a last little flutter.
static func _feather_impact() -> AudioStreamWAV:
	var b := _buf(0.26)
	var rng := _rng(7402)
	_noise(b, rng, 0.0, 0.18, 700.0, 450.0, 1.0, 0.9, 0.008, 2.2, 1)
	_noise(b, rng, 0.0, 0.14, 1400.0, 900.0, 1.0, 0.4, 0.006, 2.4)
	_noise(b, rng, 0.08, 0.16, 1100.0, 800.0, 0.9, 0.3, 0.02, 1.5, 0, 26.0, 0.9)
	return _to_wav(b, IMPACT_LOUD * 0.75)


# ---------- Choir Note: a glowing musical note ----------

# A short sung chord swooping up into place (G major), over a breath of air.
static func _choir_throw() -> AudioStreamWAV:
	var b := _buf(0.42)
	var rng := _rng(7501)
	_choir(b, rng, 0.0, 0.42, [392.0, 494.0, 587.0, 784.0], 1.0, 0.035, 1.4, 4.0, 0.12)
	_noise(b, rng, 0.0, 0.3, 900.0, 1500.0, 0.9, 0.18, 0.04, 1.6)
	return _to_wav(b, THROW_LOUD)


# A little sung "ahh!" stab (C major, bright and open), with a bell tink on top.
static func _choir_impact() -> AudioStreamWAV:
	var b := _buf(0.4)
	var rng := _rng(7502)
	_choir(b, rng, 0.0, 0.4, [523.0, 659.0, 784.0, 1046.0], 1.0, 0.01, 1.8, 1.0, 0.04,
			[[850.0, 1.0, 0.12], [1250.0, 0.7, 0.1], [2800.0, 0.25, 0.08]])
	_partial(b, 0.0, 2093.0, 0.06, 14.0, 0.003)
	return _to_wav(b, IMPACT_LOUD * 0.95)


# ---------- Holy Scripture: a heavy glowing book ----------

# A heavy page-flap "whoomp": a deep air push and a low swell, with pages riffling as it tumbles.
static func _book_throw() -> AudioStreamWAV:
	var b := _buf(0.42)
	var rng := _rng(7601)
	_noise(b, rng, 0.0, 0.42, 160.0, 380.0, 0.9, 1.0, 0.05, 1.5, 1)    # the whoomp of air
	_noise(b, rng, 0.0, 0.36, 500.0, 800.0, 1.0, 0.35, 0.05, 1.6, 0, 9.0, 0.7)   # covers flapping
	_partial(b, 0.0, 95.0, 0.5, 7.0, 0.04, 0.7, 6.0)                    # weight
	for k in 12:   # pages riffling
		var at := 0.04 + k * 0.022 + rng.randf_range(-0.004, 0.004)
		_tick(b, rng, at, rng.randf_range(1400.0, 2400.0), 0.22 * (1.0 - k / 13.0), 700.0, 0.15)
	return _to_wav(b, THROW_LOUD)


# A weighty thud, then a flutter of pages settling.
static func _book_impact() -> AudioStreamWAV:
	var b := _buf(0.55)
	var rng := _rng(7602)
	_partial(b, 0.0, 130.0, 1.0, 11.0, 0.0015, 0.5, 25.0)   # the thud, sagging in pitch
	_partial(b, 0.0, 260.0, 0.45, 18.0, 0.0015, 0.6, 30.0)
	_noise(b, rng, 0.0, 0.2, 450.0, 200.0, 1.0, 1.0, 0.002, 2.5, 1)   # the slam's body
	_tick(b, rng, 0.0, 900.0, 0.6, 300.0, 0.2)
	for k in 14:   # pages flapping down, slowing
		var at := 0.05 + 0.33 * pow(k / 14.0, 1.3) + rng.randf_range(-0.006, 0.006)
		_tick(b, rng, at, rng.randf_range(1300.0, 2300.0), 0.28 * (1.0 - k / 16.0), 600.0, 0.12)
	_noise(b, rng, 0.04, 0.4, 1600.0, 1000.0, 1.0, 0.15, 0.03, 1.5, 0, 22.0, 0.8, 12.0)
	return _to_wav(b, IMPACT_LOUD)


# ---------- Vacuum Orb: a heavenly swirling orb ----------

# A deep airy hum-swoosh: a low warm hum rising a little, with swirling air around it.
static func _vacuum_throw() -> AudioStreamWAV:
	var b := _buf(0.45)
	var rng := _rng(7701)
	_partial(b, 0.0, 110.0, 0.5, 4.0, 0.06, 1.25, 5.0, 7.0, 0.3)
	_partial(b, 0.0, 165.0, 0.3, 5.0, 0.06, 1.25, 5.0)
	_partial(b, 0.0, 220.0, 0.18, 6.0, 0.06, 1.25, 5.0)
	_noise(b, rng, 0.0, 0.45, 350.0, 1100.0, 0.6, 0.8, 0.07, 1.4, 0, 8.0, 0.55, 14.0)
	return _to_wav(b, THROW_LOUD)


# A short soft pop (the vortex has its own sounds).
static func _vacuum_impact() -> AudioStreamWAV:
	var b := _buf(0.2)
	var rng := _rng(7702)
	_partial(b, 0.0, 340.0, 0.8, 22.0, 0.002, 0.35, 45.0)
	_noise(b, rng, 0.0, 0.08, 900.0, 500.0, 1.0, 0.4, 0.002, 2.5)
	return _to_wav(b, IMPACT_LOUD * 0.7)
