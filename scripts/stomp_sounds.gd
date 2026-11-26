# The Cloud Stomp landing (Ted's wife, Nov 25: "make it sound like a superhero landing"): a short
# whoosh down into a heavy concussive THOOM. A sub-bass thump that drops in pitch, a sharp crack on
# top, ground-crunch debris grains rattling out, and a low rumble with a faint echo. Bigger drops are
# deeper, longer and throw more debris. Original synthesis only, own fixed-seed random numbers.
extends RefCounted

const RATE := 22050
const LEVELS := 4
const PEAK := 0.79   # about -2 dBFS

static var _cache := {}


# strength 0..1 (small hop .. huge drop). Snapped to one of LEVELS cached sounds, so it's cheap.
static func landing(strength: float) -> AudioStreamWAV:
	var level := clampi(roundi(clampf(strength, 0.0, 1.0) * (LEVELS - 1)), 0, LEVELS - 1)
	if not _cache.has(level):
		_cache[level] = _make(float(level) / (LEVELS - 1), level)
	return _cache[level]


static func _make(k: float, level: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210 + level * 17
	var pre := lerpf(0.07, 0.15, k)          # whoosh before the impact
	var tail := lerpf(0.75, 1.75, k)         # impact to silence
	var n := int(RATE * (pre + tail))
	var buf := PackedFloat32Array()
	buf.resize(n)
	var i0 := int(RATE * pre)

	# 1. Whoosh: noise through a low-pass whose cutoff rises toward the hit, swelling in.
	var w1 := 0.0
	var w2 := 0.0
	for i in i0:
		var u := float(i) / i0
		var a := lerpf(0.02, 0.25, u * u)
		w1 = lerpf(w1, rng.randf_range(-1.0, 1.0), a)
		w2 = lerpf(w2, w1, a)
		buf[i] += w2 * pow(u, 2.5) * lerpf(0.35, 0.5, k)

	# 2. Sub thump with a pitch drop (plus a soft-saturated copy for chest weight), and a low echo.
	var f_hi := lerpf(120.0, 95.0, k)
	var f_lo := lerpf(48.0, 30.0, k)
	var drop_rate := lerpf(16.0, 9.0, k)
	var decay := lerpf(7.0, 3.2, k)
	var echo_d := int(RATE * lerpf(0.13, 0.21, k))
	var echo_g := lerpf(0.18, 0.32, k)
	var ph := 0.0
	var thump := PackedFloat32Array()
	thump.resize(n - i0)
	for j in n - i0:
		var t := float(j) / RATE
		var f := f_lo + (f_hi - f_lo) * exp(-t * drop_rate)
		ph += TAU * f / RATE
		var env := minf(t / 0.0025, 1.0) * exp(-t * decay)
		var s := sin(ph)
		thump[j] = (s * 0.75 + tanh(s * 2.5) * 0.35) * env
	var e1 := 0.0
	for j in n - i0:
		buf[i0 + j] += thump[j] * 1.0
		if j >= echo_d:
			e1 = lerpf(e1, thump[j - echo_d], 0.08)   # the echo comes back duller
			buf[i0 + j] += e1 * echo_g * 3.0

	# 3. Crack: a bright, very short noise burst (white minus its low-passed self).
	var c_lp := 0.0
	var crack_len := int(RATE * 0.08)
	for j in crack_len:
		var t := float(j) / RATE
		var wn := rng.randf_range(-1.0, 1.0)
		c_lp = lerpf(c_lp, wn, 0.15)
		var hp := wn - c_lp
		buf[i0 + j] += (hp * 0.7 + c_lp * 0.9) * minf(t / 0.0008, 1.0) * exp(-t * lerpf(90.0, 60.0, k)) * lerpf(0.55, 0.75, k)

	# 4. Debris: crunchy band-passed noise grains scattered after the hit, thinning out.
	var grains := int(lerpf(10.0, 42.0, k))
	var spread := tail * lerpf(0.35, 0.55, k)
	for g in grains:
		var start := 0.006 + spread * pow(rng.randf(), 1.8)
		var glen := int(RATE * rng.randf_range(0.008, lerpf(0.025, 0.045, k)))
		var amp := rng.randf_range(0.12, 0.32) * exp(-start * 3.0 / spread)
		var bright := rng.randf_range(0.25, 0.6)   # band center: lp minus slower lp
		var dull := bright * rng.randf_range(0.1, 0.25)
		var b1 := 0.0
		var b2 := 0.0
		var si := i0 + int(start * RATE)
		for j in glen:
			if si + j >= n:
				break
			var gu := float(j) / glen
			var wn := rng.randf_range(-1.0, 1.0)
			b1 = lerpf(b1, wn, bright)
			b2 = lerpf(b2, wn, dull)
			buf[si + j] += (b1 - b2) * amp * sin(gu * PI) * 1.6

	# 5. Rumble: heavily smoothed noise, rolling off long after the hit.
	var r1 := 0.0
	var r2 := 0.0
	var r_decay := lerpf(4.5, 1.8, k)
	for j in n - i0:
		var t := float(j) / RATE
		r1 = lerpf(r1, rng.randf_range(-1.0, 1.0), 0.03)
		r2 = lerpf(r2, r1, 0.04)
		buf[i0 + j] += r2 * 7.0 * lerpf(0.5, 0.8, k) * minf(t / 0.02, 1.0) * exp(-t * r_decay)

	# Finish: DC block, fade the very ends to exact silence, normalise to the target peak.
	var x1 := 0.0
	var y1 := 0.0
	var peak := 0.0
	var fade := int(RATE * 0.12)
	for i in n:
		var x := buf[i]
		var y := x - x1 + 0.995 * y1
		x1 = x
		y1 = y
		var tail_g := 1.0
		if i > n - fade:
			tail_g = float(n - i) / fade
			tail_g *= tail_g
		y *= tail_g * minf(float(i) / 64.0, 1.0)
		buf[i] = y
		peak = maxf(peak, absf(y))
	var gain := PEAK / maxf(peak, 0.0001)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i] * gain, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav
