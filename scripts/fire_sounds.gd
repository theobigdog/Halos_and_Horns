# Hellfire's sounds (fire.gd plays them). Synthesized in code like everything else (sfx.gd), each made
# once and shared. Each uses its own RandomNumberGenerator with a fixed seed, never the global randf().
#   whoosh(): the fireball flung through the air, a filtered-noise rush that sweeps down (doppler) over a roar.
#   ignite(): it lands, "FWOOMP": a low thump, a bright burst of crackle and an air rush swelling up.
#   burn():   a seamless ~4 s loop of rushing, roaring flame with a faint hellish growl, plus crackles and pops.
extends RefCounted

const Sfx = preload("res://scripts/sfx.gd")
const RATE := Sfx.RATE

static var _cache := {}


# The fireball flying through the air (plays once as it's thrown).
static func whoosh() -> AudioStream:
	if not _cache.has("whoosh"):
		_cache["whoosh"] = _make_whoosh()
	return _cache["whoosh"]


# The moment it lands and bursts into flame (plays once).
static func ignite() -> AudioStream:
	if not _cache.has("ignite"):
		_cache["ignite"] = _make_ignite()
	return _cache["ignite"]


# The fire burning (loops for as long as it burns: fire.gd fades it out at the end).
static func burn() -> AudioStream:
	if not _cache.has("burn"):
		_cache["burn"] = _make_burn()
	return _cache["burn"]


# ---------- building blocks ----------

# Chamberlin state-variable filter coefficient for a centre frequency (stable well below RATE / 6).
static func _svf_f(hz: float) -> float:
	return 2.0 * sin(PI * minf(hz, 3500.0) / RATE)


# One-pole low-pass coefficient for a cutoff frequency.
static func _lp_a(hz: float) -> float:
	return 1.0 - exp(-TAU * hz / RATE)


static func _to_wav(buf: PackedFloat32Array, gain: float) -> AudioStreamWAV:
	var n := buf.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var s := buf[i] * gain
		if absf(s) > 0.7:   # soft knee above 0.7: rounds off the odd peak, never a hard clip
			s = signf(s) * (0.7 + 0.29 * tanh((absf(s) - 0.7) / 0.29))
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav


# Smooth random wobble: `count` random knots in -1..1, read back with cosine interpolation. Periodic over
# u = 0..1 (the last knot leads back into the first), so it suits loops too.
static func _knots(rng: RandomNumberGenerator, count: int) -> PackedFloat32Array:
	var k := PackedFloat32Array()
	k.resize(count)
	for i in count:
		k[i] = rng.randf_range(-1.0, 1.0)
	return k


static func _wobble(k: PackedFloat32Array, u: float) -> float:
	var c := k.size()
	var p := fposmod(u, 1.0) * c
	var i := int(p) % c
	var f := (1.0 - cos((p - floorf(p)) * PI)) * 0.5
	return lerpf(k[i], k[(i + 1) % c], f)


# Adds one crackle/pop at sample `at` into buf (wrapping round when `wrap` is set, for the loop).
# A snap is a few milliseconds of bright, fast-decaying noise; a pop also rings a short resonant tick.
static func _crackle(buf: PackedFloat32Array, at: int, amp: float, rng: RandomNumberGenerator, wrap: bool) -> void:
	var n := buf.size()
	var len_n := int(RATE * rng.randf_range(0.004, 0.018))
	var decay := rng.randf_range(250.0, 900.0)
	var ring_hz := rng.randf_range(900.0, 3200.0)
	var ring := rng.randf_range(0.0, 0.8)
	var prev := 0.0
	for j in len_n:
		var k := at + j
		if k >= n:
			if not wrap:
				return
			k -= n
		var t := float(j) / RATE
		var white := rng.randf_range(-1.0, 1.0)
		var hp := white - prev   # first difference: crisp, no low end
		prev = white
		var env := exp(-t * decay)
		buf[k] += amp * env * (hp * 0.6 + ring * sin(TAU * ring_hz * t))


# ---------- the sounds ----------

static func _make_whoosh() -> AudioStreamWAV:
	var seconds := 0.6
	var n := int(RATE * seconds)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6661
	var lo := 0.0
	var band := 0.0
	var turb_k := _knots(rng, 14)
	var roar1 := 0.0
	var roar2 := 0.0
	var growl := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := float(i) / n
		var white := rng.randf_range(-1.0, 1.0)
		# the rush: band-passed noise whose centre falls as the fireball passes (doppler)
		var fc := lerpf(2600.0, 420.0, pow(u, 0.8))
		var f := _svf_f(fc)
		var hi := white - lo - 0.9 * band
		band += f * hi
		lo += f * band
		# fluttering turbulence on top
		var turb := _wobble(turb_k, u * 0.93)
		# the roaring body: low-passed noise
		roar1 = lerpf(roar1, white, _lp_a(260.0))
		roar2 = lerpf(roar2, roar1, _lp_a(260.0))
		growl += TAU * lerpf(95.0, 58.0, u) / RATE
		# loudness: swells to a peak about 40% in, then trails away
		var env := pow(sin(PI * pow(u, 0.75)), 1.6) * minf(t / 0.01, 1.0)
		var rush := band * 0.95 * (1.0 + turb * 0.45)
		var body := roar2 * 2.6 * (0.85 + turb * 0.35)
		var hell := (sin(growl) + 0.4 * sin(growl * 2.0)) * 0.12 * (1.0 + roar2 * 6.0)
		buf[i] = (rush + body + hell) * env
	return _to_wav(buf, 0.8)


static func _make_ignite() -> AudioStreamWAV:
	var seconds := 1.3
	var n := int(RATE * seconds)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6662
	var ph := 0.0
	var lo := 0.0
	var band := 0.0
	var dull := 0.0
	var dull2 := 0.0
	var prev := 0.0
	var turb_k := _knots(rng, 16)
	for i in n:
		var t := float(i) / RATE
		var u := float(i) / n
		var white := rng.randf_range(-1.0, 1.0)
		# the "fw-OOMP" thump: a falling low sine with a soft attack
		ph += TAU * lerpf(110.0, 38.0, minf(t / 0.35, 1.0)) / RATE
		var thump := (sin(ph) + 0.25 * sin(ph * 2.0)) * exp(-t * 7.0) * minf(t / 0.006, 1.0) * 0.6
		dull = lerpf(dull, white, _lp_a(180.0))
		dull2 = lerpf(dull2, dull, _lp_a(180.0))
		var boom := dull2 * 5.0 * exp(-t * 5.0)
		# a bright burst: high-passed noise flashing at impact
		var bright := (white - prev) * 0.5 * exp(-t * 22.0)
		prev = white
		# the air rush swelling: band-passed noise opening upward, then settling (into the burn loop)
		var fc := lerpf(300.0, 1400.0, minf(t / 0.25, 1.0)) - 500.0 * maxf(t - 0.25, 0.0)
		var f := _svf_f(maxf(fc, 450.0))
		var hi := white - lo - 1.0 * band
		band += f * hi
		lo += f * band
		var turb := _wobble(turb_k, u * 0.94)
		var swell := sin(PI * minf(t / 0.24, 1.0) * 0.5) * exp(-maxf(t - 0.2, 0.0) * 2.6)
		var rush := band * 1.2 * swell * (1.0 + turb * 0.4)
		buf[i] = (thump + boom + bright + rush) * pow(1.0 - u, 0.7)
	# a shower of crackles, thickest right after impact
	for c in 55:
		var at := int(RATE * 0.9 * pow(rng.randf(), 2.2)) + int(RATE * 0.01)
		var amp := 0.5 * pow(rng.randf(), 1.5) * exp(-float(at) / RATE * 2.5) + 0.04
		_crackle(buf, at, amp, rng, false)
	return _to_wav(buf, 0.68)


# The burn loop is built 4 s long plus a 0.25 s overlap; the overlap is crossfaded (equal power) into the
# start so the noise beds join seamlessly, and the crackles are placed afterwards wrapping round the end.
static func _make_burn() -> AudioStreamWAV:
	var seconds := 4.0
	var n := int(RATE * seconds)
	var x := int(RATE * 0.25)
	var raw := PackedFloat32Array()
	raw.resize(n + x)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6663
	var lo := 0.0
	var band := 0.0
	var r1 := 0.0
	var r2 := 0.0
	var surge_k := _knots(rng, 13)    # slow surges, about 3 a second
	var flick_k := _knots(rng, 37)    # quicker flicker, about 9 a second
	var growl_k := _knots(rng, 5)
	var hiss_prev := 0.0
	var hiss_lp := 0.0
	var growl := 0.0
	var f_roar := _svf_f(520.0)
	var a_rumble := _lp_a(110.0)
	var a_hiss := _lp_a(4000.0)
	for i in n + x:
		var t := float(i) / RATE
		var white := rng.randf_range(-1.0, 1.0)
		# turbulence: a slow surge (about 1 Hz) and a quicker flicker (~9 Hz)
		# (periodic over the loop length, so they need no crossfade)
		var u := float(i) / n
		var surge := 1.0 + 0.4 * _wobble(surge_k, u)
		var flutter := 1.0 + 0.25 * _wobble(flick_k, u)
		# rushing roar: wide band-passed noise
		var hi := white - lo - 1.3 * band
		band += f_roar * hi
		lo += f_roar * band
		# low rumble
		r1 = lerpf(r1, white, a_rumble)
		r2 = lerpf(r2, r1, a_rumble)
		# soft high hiss (band-limited, so not harsh)
		hiss_lp = lerpf(hiss_lp, white, a_hiss)
		var hiss := hiss_lp - hiss_prev
		hiss_prev = hiss_lp
		# a faint hellish growl, rising and falling with the surge
		growl += TAU * (52.0 + 4.0 * sin(TAU * 0.25 * t)) / RATE
		var gl := 0.5 + 0.5 * _wobble(growl_k, u)
		var g := (sin(growl) + 0.5 * sin(growl * 2.0 + 0.3) + 0.2 * sin(growl * 3.0)) * 0.06 * gl * (0.7 + r2 * 6.0)
		raw[i] = band * 0.5 * surge * flutter + r2 * 1.8 * surge + hiss * 0.12 * flutter + g
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		if i < x:
			var w := float(i) / x * PI * 0.5
			buf[i] = raw[i] * sin(w) + raw[n + i] * cos(w)
		else:
			buf[i] = raw[i]
	# crackles and pops at irregular times: mostly little snaps, now and then a louder pop
	var at := 0.0
	while true:
		at += RATE * (0.03 + 0.22 * pow(rng.randf(), 1.8))
		if at >= n:
			break
		var big := rng.randf() < 0.12
		var amp := rng.randf_range(1.0, 1.5) if big else 0.25 + 0.6 * pow(rng.randf(), 2.0)
		_crackle(buf, int(at), amp, rng, true)
		if big and rng.randf() < 0.6:   # a pop often sets off a little cluster of snaps
			for c in rng.randi_range(2, 5):
				_crackle(buf, int(at) + int(RATE * rng.randf_range(0.01, 0.09)), amp * rng.randf_range(0.15, 0.4), rng, true)
	var wav := _to_wav(buf, 0.44)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav
