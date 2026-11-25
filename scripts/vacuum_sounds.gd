# The Vacuum Orb's sounds (vortex.gd plays them). Synthesized in code like everything else (sfx.gd); each
# made once and cached. Each uses its own RandomNumberGenerator with a fixed seed, never the global randf().
#   open():        the orb bursts open: a soft deep boom, an upward rush of wind, a rising run of bells
#                  and a choir "ahh" swelling into the vortex.
#   suck_loop():   a seamless 4 s loop: a rushing, swirling suction roar (noise with a slowly sweeping
#                  band and a flanger for the phasing swirl) over a deep pull, a soft choir pad and the
#                  odd high bell glint. Nothing in it is harsh, so it still sounds right pitched up ~1.4x.
#   caught_loop(): a seamless 2 s loop layered on top while a demon is caught: a blazing choir swinging
#                  between D major and Bb major, gated in a tense 4-a-second pulse, a two-tone bell
#                  alarm, a heartbeat throb underneath and crackling, sizzling holy energy.
#   close():       the vortex imploding: the rush sucked down into a soft thump, then a falling shimmer
#                  of bells and a fading choir.
extends RefCounted

const Sfx = preload("res://scripts/sfx.gd")
const RATE := Sfx.RATE

static var _cache := {}


# The moment the orb bursts open into a vortex (plays once).
static func open() -> AudioStream:
	if not _cache.has("open"):
		_cache["open"] = _make_open()
	return _cache["open"]


# The vortex sucking (LOOPS while it lasts; vortex.gd can raise its pitch/volume as it tightens).
static func suck_loop() -> AudioStream:
	if not _cache.has("suck"):
		_cache["suck"] = _make_suck()
	return _cache["suck"]


# A demon is caught in it (LOOPS while one is; layered over suck_loop, drastically different).
static func caught_loop() -> AudioStream:
	if not _cache.has("caught"):
		_cache["caught"] = _make_caught()
	return _cache["caught"]


# The vortex collapsing at the end (plays once).
static func close() -> AudioStream:
	if not _cache.has("close"):
		_cache["close"] = _make_close()
	return _cache["close"]


# ---------- building blocks ----------

const TABLE := 512
const BLOCK := 16   # samples per control-rate step (slow wobbles, vibrato, chord fades)

# Chamberlin state-variable filter coefficient for a centre frequency (stable well below RATE / 6).
static func _svf_f(hz: float) -> float:
	return 2.0 * sin(PI * clampf(hz, 20.0, 3500.0) / RATE)


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


static func _looped(buf: PackedFloat32Array, gain: float) -> AudioStreamWAV:
	var wav := _to_wav(buf, gain)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = buf.size()
	return wav


# Smooth random wobble: `count` random knots in -1..1, read back with cosine interpolation. Periodic over
# u = 0..1, so it suits loops.
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


# One cycle of a sung vowel at pitch f0: harmonics falling off as 1/k, shaped by three formant peaks
# (an open "ah" by default). Read back by _sing(); one table per pitch keeps the formants in place.
static func _vowel(f0: float, formants := [[720.0, 1.0], [1150.0, 0.55], [2600.0, 0.25]]) -> PackedFloat32Array:
	var tab := PackedFloat32Array()
	tab.resize(TABLE + 1)
	var amps := []
	var k := 1
	while f0 * k < 4500.0 and k <= 24:
		var hz := f0 * k
		var g := 0.12
		for fm in formants:
			var d: float = (hz - fm[0]) / (fm[0] * 0.22)
			g += fm[1] * exp(-d * d)
		amps.append(g / sqrt(float(k)))
		k += 1
	var peak := 0.0
	for i in TABLE:
		var s := 0.0
		for h in amps.size():
			s += amps[h] * sin(TAU * (h + 1) * i / TABLE)
		tab[i] = s
		peak = maxf(peak, absf(s))
	for i in TABLE:
		tab[i] /= peak
	tab[TABLE] = tab[0]
	return tab



# Adds one sung voice (a _vowel table at f0 Hz with a vibrato of `depth` x f0 at `vr` Hz) into buf,
# loudness from amp_at(t). Exact phase at every BLOCK boundary, interpolated between, so a voice whose
# f0 and vr are whole multiples of 1 / loop length repeats exactly across the loop seam.
static func _sing(buf: PackedFloat32Array, tab: PackedFloat32Array, f0: float, depth: float, vr: float,
		off: float, amp_at: Callable, from := 0, to := -1) -> void:
	if to < 0:
		to = buf.size()
	var vd := depth * f0 / vr
	var i0 := from - from % BLOCK
	while i0 < to:
		var ta := float(i0) / RATE
		var tb := float(i0 + BLOCK) / RATE
		var pa := f0 * ta + vd * sin(TAU * vr * ta + off)
		var pb := f0 * tb + vd * sin(TAU * vr * tb + off)
		var aa: float = amp_at.call(ta)
		var ab: float = amp_at.call(tb)
		if absf(aa) + absf(ab) > 0.0001:
			var j0 := maxi(from - i0, 0)
			var j1 := mini(to - i0, BLOCK)
			var dp := (pb - pa) / BLOCK
			var dam := (ab - aa) / BLOCK
			var ph := pa - floorf(pa) + dp * j0   # phases stay small, so the table index stays accurate
			var am := aa + dam * j0
			for j in range(j0, j1):
				var p := (ph - floorf(ph)) * TABLE
				var k := int(p)
				var s := tab[k]
				buf[i0 + j] += (s + (tab[k + 1] - s) * (p - k)) * am
				ph += dp
				am += dam
		i0 += BLOCK


# A struck bell added into buf at sample `at`: a few inharmonic partials, each a damped resonator
# (two multiply-adds a sample). `wrap` wraps it round the end of a loop.
static func _bell(buf: PackedFloat32Array, at: int, hz: float, amp: float, decay: float, wrap: bool) -> void:
	var n := buf.size()
	var parts := [[1.0, 1.0, 1.0], [2.0, 0.35, 1.6], [2.76, 0.3, 2.2], [5.4, 0.12, 3.5]]
	for pt in parts:
		var f: float = hz * pt[0]
		if f > RATE * 0.4:
			continue
		var d: float = decay * pt[2]
		var r := exp(-d / RATE)
		var w := TAU * f / RATE
		var c := 2.0 * r * cos(w)
		var r2 := r * r
		var len_n := mini(int(RATE * 6.9 / d), n)
		var y2 := 0.0
		var y1 := r * sin(w)
		var a: float = amp * pt[1]
		for j in range(1, len_n):
			var k := at + j
			if k >= n:
				if not wrap:
					break
				k -= n
			buf[k] += a * y1
			var y := c * y1 - r2 * y2
			y2 = y1
			y1 = y


# One crackle of holy energy at sample `at`: a few ms of bright noise with a high ringing tick.
static func _crackle(buf: PackedFloat32Array, at: int, amp: float, rng: RandomNumberGenerator, wrap: bool) -> void:
	var n := buf.size()
	var len_n := int(RATE * rng.randf_range(0.003, 0.014))
	var decay := rng.randf_range(300.0, 1000.0)
	var ring_hz := rng.randf_range(2200.0, 5200.0)
	var prev := 0.0
	for j in len_n:
		var k := at + j
		if k >= n:
			if not wrap:
				return
			k -= n
		var t := float(j) / RATE
		var white := rng.randf_range(-1.0, 1.0)
		var hp := white - prev
		prev = white
		buf[k] += amp * exp(-t * decay) * (hp * 0.5 + 0.6 * sin(TAU * ring_hz * t))


# ---------- the sounds ----------

static func _make_suck() -> AudioStreamWAV:
	var seconds := 4.0
	var n := int(RATE * seconds)
	var x := int(RATE * 0.3)
	var raw := PackedFloat32Array()
	raw.resize(n + x)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7701
	var swirl_k := _knots(rng, 9)     # the whistling band sweeping round, about 2 a second
	var surge_k := _knots(rng, 7)
	var lo := 0.0
	var band := 0.0
	var lo2 := 0.0
	var band2 := 0.0
	var r1 := 0.0
	var r2 := 0.0
	var a_rumble := _lp_a(140.0)
	var f_air := _svf_f(2300.0)
	# 1) the rushing wind, made n + x long; the overlap is crossfaded into the start below.
	#    The swirl and surge move slowly, so they're worked out once per BLOCK samples.
	var f := 0.0
	var surge := 1.0
	for i in n + x:
		if i % BLOCK == 0:
			var u := float(i) / n
			f = _svf_f(820.0 * pow(2.0, 0.75 * _wobble(swirl_k, u)))
			surge = 1.0 + 0.3 * _wobble(surge_k, u)
		var white := rng.randf_range(-1.0, 1.0)
		var hi := white - lo - 0.55 * band   # fairly resonant: a whistling, howling wind
		band += f * hi
		lo += f * band
		var hi2 := white - lo2 - 1.4 * band2
		band2 += f_air * hi2
		lo2 += f_air * band2
		r1 += (white - r1) * a_rumble
		r2 += (r1 - r2) * a_rumble
		raw[i] = (band * 0.32 + band2 * 0.16) * surge + r2 * 3.2 * (2.0 - surge)
	# the crossfaded wind, with the loop's last PAD samples copied in front so the delay taps can
	# read back past the start without wrapping indices (wind[PAD + i] is sample i)
	const PAD := 256
	var wind := PackedFloat32Array()
	wind.resize(n + PAD)
	for i in n:
		var v := raw[i]
		if i < x:
			var w := float(i) / x * PI * 0.5
			v = raw[i] * sin(w) + raw[n + i] * cos(w)
		wind[PAD + i] = v
	for i in PAD:
		wind[i] = wind[n + i]
	# 2) flanger + deep pull, then the choir pad: all exactly periodic over the loop (frequencies are
	#    multiples of 1/4 Hz), so the flanger reads the wind wrapping round and nothing needs crossfading.
	#    Two sweeping delay taps (0.5 Hz and 0.75 Hz) give the jet-like phasing swirl.
	var buf := PackedFloat32Array()
	buf.resize(n)
	var blocks := n / BLOCK
	var pw := TAU * 41.25 / RATE   # the deep pull's sine, by rotation (and its octave by double angle)
	var pc := cos(pw)
	var ps := sin(pw)
	var sn := 0.0
	var cn := 1.0
	for bk in blocks:
		var i0 := bk * BLOCK
		var ta := float(i0) / RATE
		var tb := float(i0 + BLOCK) / RATE
		var da := PAD - RATE * (0.0012 + 0.0055 * (0.5 + 0.5 * sin(TAU * 0.5 * ta)))
		var db := PAD - RATE * (0.0012 + 0.0055 * (0.5 + 0.5 * sin(TAU * 0.5 * tb)))
		var ea := PAD - RATE * (0.0025 + 0.0040 * (0.5 + 0.5 * sin(TAU * 0.75 * ta + 1.7)))
		var eb := PAD - RATE * (0.0025 + 0.0040 * (0.5 + 0.5 * sin(TAU * 0.75 * tb + 1.7)))
		# the deep pull: a low hum swelling twice a loop
		var swell := (0.55 + 0.45 * sin(TAU * 0.5 * ta - 1.2)) * 0.32
		sn = sin(pw * i0)   # re-synced every block, so no drift
		cn = cos(pw * i0)
		var dd := (db - da) / BLOCK
		var de := (eb - ea) / BLOCK
		for j in BLOCK:
			var i := i0 + j
			var p1 := i + da + dd * j
			var p2 := i + ea + de * j
			var i1 := int(p1)
			var i2 := int(p2)
			var a1 := wind[i1]
			var a2 := wind[i2]
			var tap1 := a1 + (wind[i1 + 1] - a1) * (p1 - i1)
			var tap2 := a2 + (wind[i2 + 1] - a2) * (p2 - i2)
			buf[i] = wind[PAD + i] + 0.75 * tap1 - 0.45 * tap2 + (sn + 0.7 * sn * cn) * swell
			var s2 := sn * pc + cn * ps
			cn = cn * pc - sn * ps
			sn = s2
	# the choir pad, each voice breathing at its own rate with a gentle vibrato (a soft "oo")
	var chord := [[146.75, 0.55], [220.0, 0.5], [370.0, 0.4], [587.25, 0.22]]
	for v in chord.size():
		var tab := _vowel(chord[v][0], [[400.0, 1.0], [800.0, 0.5], [2500.0, 0.15]])
		var vr := 4.75 + 0.25 * v
		var br := 0.25 * (v + 1)
		_sing(buf, tab, chord[v][0], 0.005, vr, float(v), func(t: float) -> float:
			return 0.16 * chord[v][1] * (0.6 + 0.4 * sin(TAU * br * t + v * 1.3)))
	# 3) the odd high bell glint, from a heavenly pentatonic, wrapping round the loop end
	var bells := [1174.75, 1318.5, 1480.0, 1760.0, 1975.5, 2349.25]
	var at := 0.0
	while true:
		at += RATE * rng.randf_range(0.35, 0.8)
		if at >= n:
			break
		_bell(buf, int(at), bells[rng.randi_range(0, bells.size() - 1)], rng.randf_range(0.03, 0.07), 3.0, true)
	return _looped(buf, 0.38)


# The caught loop's tense pulse: 4 swells a second, a quick rise and a slower fall, never fully silent.
static func _gate(t: float) -> float:
	var beat := fposmod(t * 4.0, 1.0)
	return 0.45 + 0.55 * minf(beat / 0.06, 1.0) * exp(-beat * 2.8)


# How much of chord A (0..1, linear) at time t in the caught loop: A on the first half, B on the
# second, 40 ms ramps centred on each change, the one at the seam wrapping round.
static func _chord_a(t: float, loop: float) -> float:
	var h := loop * 0.5
	var r := 0.02
	t = fposmod(t, loop)
	if t < r:
		return 0.5 + 0.5 * t / r
	if t > loop - r:
		return 0.5 - 0.5 * (loop - t) / r
	if t < h - r:
		return 1.0
	if t < h + r:
		return 0.5 - 0.5 * (t - h) / r
	return 0.0


static func _make_caught() -> AudioStreamWAV:
	var seconds := 2.0
	var n := int(RATE * seconds)
	var x := int(RATE * 0.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7702
	# the blazing choir: D major for a second, then Bb major (all multiples of 1/2 Hz: exactly periodic)
	var ch_a := [[146.5, 0.7], [293.5, 0.55], [440.0, 0.5], [587.5, 0.45], [740.0, 0.35], [880.0, 0.25]]
	var ch_b := [[116.5, 0.7], [233.0, 0.55], [349.0, 0.5], [466.0, 0.45], [587.5, 0.35], [698.5, 0.25]]
	# sizzle: bright band-passed noise, crossfaded seamless like the suck wind
	var raw := PackedFloat32Array()
	raw.resize(n + x)
	var lo := 0.0
	var band := 0.0
	var f_hiss := _svf_f(3300.0)
	for i in n + x:
		var white := rng.randf_range(-1.0, 1.0)
		var hi := white - lo - 0.9 * band
		band += f_hiss * hi
		lo += f_hiss * band
		raw[i] = band
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var hiss := raw[i]
		if i < x:
			var w := float(i) / x * PI * 0.5
			hiss = raw[i] * sin(w) + raw[n + i] * cos(w)
		# the tense pulse: 4 swells a second, a quick rise and a slower fall, never fully silent
		var beat := fposmod(t * 4.0, 1.0)
		var gate := _gate(t)
		# the heartbeat throb under it, twice a second (D2)
		var hb := fposmod(t * 2.0, 1.0)
		var throb := sin(TAU * 73.5 * t) * minf(hb / 0.01, 1.0) * exp(-hb * 9.0)
		buf[i] = throb * 0.5 + hiss * 0.1 * (0.4 + 0.6 * gate)
	# the choir: A on the first half, B on the second, a 40 ms equal-power crossfade centred on each
	# change (the one at the loop seam wraps round), pulsing with the gate
	for v in ch_a.size():
		var vr := 5.0 + 0.5 * (v % 3)
		var tab_a := _vowel(ch_a[v][0])
		var tab_b := _vowel(ch_b[v][0])
		_sing(buf, tab_a, ch_a[v][0], 0.007, vr, float(v), func(t: float) -> float:
			return 0.3 * ch_a[v][1] * _gate(t) * sin(_chord_a(t, seconds) * PI * 0.5))
		_sing(buf, tab_b, ch_b[v][0], 0.007, vr, float(v), func(t: float) -> float:
			return 0.3 * ch_b[v][1] * _gate(t) * cos(_chord_a(t, seconds) * PI * 0.5))
	# the two-tone bell alarm: A6 and D7 on alternating eighths, a little behind each choir pulse
	for b in 8:
		var hz := 1760.0 if b % 2 == 0 else 2349.25
		_bell(buf, int(RATE * (0.25 * b + 0.01)), hz, 0.09, 6.0, true)
	# crackling holy energy
	var at := 0.0
	while true:
		at += RATE * (0.02 + 0.12 * pow(rng.randf(), 1.6))
		if at >= n:
			break
		_crackle(buf, int(at), rng.randf_range(0.08, 0.35), rng, true)
	return _looped(buf, 0.95)


static func _make_open() -> AudioStreamWAV:
	var seconds := 1.5
	var n := int(RATE * seconds)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7703
	var lo := 0.0
	var band := 0.0
	var d1 := 0.0
	var d2 := 0.0
	var ph := 0.0
	var turb_k := _knots(rng, 11)
	for i in n:
		var t := float(i) / RATE
		var u := float(i) / n
		var white := rng.randf_range(-1.0, 1.0)
		# the soft deep boom: a falling sine and a puff of low noise
		ph += TAU * lerpf(95.0, 38.0, minf(t / 0.4, 1.0)) / RATE
		var thump := (sin(ph) + 0.2 * sin(ph * 2.0)) * exp(-t * 6.0) * minf(t / 0.008, 1.0)
		d1 = lerpf(d1, white, _lp_a(160.0))
		d2 = lerpf(d2, d1, _lp_a(160.0))
		var puff := d2 * 5.0 * exp(-t * 7.0)
		# the rush of wind opening upward, then swirling
		var fc := lerpf(260.0, 2200.0, pow(minf(t / 0.32, 1.0), 1.5)) - 1100.0 * minf(maxf(t - 0.32, 0.0) / 0.6, 1.0)
		fc *= pow(2.0, 0.25 * _wobble(turb_k, u))
		var f := _svf_f(fc)
		var hi := white - lo - 0.6 * band
		band += f * hi
		lo += f * band
		var swell := sin(PI * 0.5 * minf(t / 0.3, 1.0)) * (1.0 - smoothstep(0.35, 1.5, t) * 0.85)
		var rush := band * 0.5 * swell
		buf[i] = thump * 0.75 + puff + rush
	# the choir "ahh" blooming
	var chord := [[146.75, 0.5], [293.75, 0.45], [370.0, 0.4], [440.0, 0.35], [587.25, 0.25]]
	for v in chord.size():
		_sing(buf, _vowel(chord[v][0]), chord[v][0], 0.006, 5.0, float(v), func(t: float) -> float:
			return 0.22 * chord[v][1] * smoothstep(0.05, 0.4, t) * (1.0 - smoothstep(0.6, 1.5, t)))
	# a rising run of bells (D major arpeggio), struck as it bursts open
	var run := [587.25, 740.0, 880.0, 1174.75, 1480.0, 1760.0, 2349.25]
	for b in run.size():
		_bell(buf, int(RATE * (0.02 + 0.045 * b)), run[b], 0.16 - 0.012 * b, 3.5, false)
	# fade the tail out so it ends cleanly
	var tail := int(RATE * 0.15)
	for i in tail:
		buf[n - 1 - i] *= float(i) / tail
	return _to_wav(buf, 0.8)


static func _make_close() -> AudioStreamWAV:
	var seconds := 1.6
	var n := int(RATE * seconds)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7704
	var hit := 0.42   # the moment it collapses
	var lo := 0.0
	var band := 0.0
	var d1 := 0.0
	var d2 := 0.0
	var ph := 0.0
	var sw := 0.0
	for i in n:
		var t := float(i) / RATE
		var white := rng.randf_range(-1.0, 1.0)
		# the rush, sucked down and in: band sweeping from high to low, swelling until the collapse
		var k := minf(t / hit, 1.0)
		var f := _svf_f(lerpf(2400.0, 220.0, pow(k, 1.4)))
		var hi := white - lo - 0.5 * band
		band += f * hi
		lo += f * band
		var pre := pow(k, 2.2) * (1.0 if t < hit else exp(-(t - hit) * 30.0)) * minf(t / 0.03, 1.0)
		var rush := band * 0.55 * pre
		# a swirling tone sliding down into the centre
		sw += TAU * lerpf(900.0, 90.0, pow(k, 0.8)) / RATE
		var swirl := sin(sw + 0.6 * sin(sw * 0.5)) * pre * 0.12
		# the soft thump as it closes
		var th := 0.0
		var puff := 0.0
		d1 = lerpf(d1, white, _lp_a(150.0))
		d2 = lerpf(d2, d1, _lp_a(150.0))
		if t >= hit:
			var s := t - hit
			ph += TAU * lerpf(85.0, 36.0, minf(s / 0.3, 1.0)) / RATE
			th = (sin(ph) + 0.15 * sin(ph * 2.0)) * exp(-s * 7.0) * minf(s / 0.006, 1.0)
			puff = d2 * 4.0 * exp(-s * 10.0)
		buf[i] = rush + swirl + th * 0.8 + puff
	# a soft high choir ("ee") fading after it
	var chord := [[293.75, 0.45], [440.0, 0.4], [587.25, 0.35], [740.0, 0.25], [880.0, 0.2]]
	for v in chord.size():
		var tab := _vowel(chord[v][0], [[350.0, 1.0], [2000.0, 0.4], [2800.0, 0.2]])
		_sing(buf, tab, chord[v][0], 0.005, 5.5, float(v), func(t: float) -> float:
			return 0.14 * chord[v][1] * smoothstep(hit - 0.05, hit + 0.12, t) * exp(-maxf(t - hit - 0.1, 0.0) * 2.2),
			int(RATE * (hit - 0.05)))
	# a falling shimmer of bells after the collapse
	var run := [2349.25, 1975.5, 1760.0, 1480.0, 1174.75, 880.0]
	for b in run.size():
		_bell(buf, int(RATE * (hit + 0.03 + 0.06 * b)), run[b], 0.1 - 0.008 * b, 3.2, false)
	var tail := int(RATE * 0.2)
	for i in tail:
		buf[n - 1 - i] *= float(i) / tail
	return _to_wav(buf, 0.85)
