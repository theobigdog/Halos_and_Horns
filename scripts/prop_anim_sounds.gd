# Sounds for animated props (Ted's prop list, Nov 26): a lamp's chain click, a lighter's click, chewing,
# a cork pop, a chest's creak and latch, coins, a keg's glug, a squirt, scribbling, a gas burner, the
# oven's ding, a rocking chair's creak, a fuse's fizz and the big KABOOM. All quiet (Ted: "quiet click",
# "quiet clatter"...), short, synthesized here from fixed-seed noise and tones (no samples), and cached.
extends RefCounted

const RATE := 22050

static var _cache := {}
static var _lock := Mutex.new()
static var _warming := false


static func get_sound(sound_name: String) -> AudioStreamWAV:
	_lock.lock()
	var have: AudioStreamWAV = _cache.get(sound_name)
	_lock.unlock()
	if have != null:
		return have
	if true:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(sound_name)
		var buf: PackedFloat32Array
		match sound_name:
			"chain": buf = _chain(rng)
			"lighter": buf = _lighter(rng)
			"squish": buf = _squish(rng)
			"chew": buf = _chew(rng, false)
			"gag": buf = _chew(rng, true)
			"clatter": buf = _clatter(rng, 5, 1.0)
			"pop": buf = _pop(rng)
			"creak": buf = _creak(rng, 0.45, 260.0)
			"latch": buf = _latch(rng)
			"tinkle": buf = _clatter(rng, 9, 2.2)
			"glug": buf = _glug(rng)
			"squirt": buf = _squirt(rng)
			"scribble": buf = _scribble(rng)
			"rush": buf = _rush(rng)
			"ding": buf = _ding()
			"thump": buf = _thump(rng)
			"rustle": buf = _rustle(rng)
			"rock": buf = _creak(rng, 0.6, 170.0)
			"fuse": buf = _fuse(rng)
			"kaboom": buf = _kaboom(rng)
			"buzz": buf = _buzz()
			_: buf = PackedFloat32Array([0.0])
		have = _wav(buf, 0.8, sound_name == "buzz")
		_lock.lock()
		_cache[sound_name] = have
		_lock.unlock()
	return have


# Sounds are made in the background at startup (like taunts), so the first press doesn't stall.
static func warm_up() -> void:
	if _warming:
		return
	_warming = true
	WorkerThreadPool.add_task(_make_all)


static func _make_all() -> void:
	for s in ["chain", "lighter", "squish", "chew", "gag", "clatter", "pop", "creak", "latch", "tinkle",
			"glug", "squirt", "scribble", "rush", "ding", "thump", "rustle", "rock", "fuse", "kaboom", "buzz"]:
		get_sound(s)


static func _new(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(RATE * seconds))
	return b


# A short bright tick (a click): a burst of noise through a resonance at `hz`.
static func _tick(b: PackedFloat32Array, at: float, hz: float, loud: float, decay: float, rng: RandomNumberGenerator) -> void:
	var i0 := int(at * RATE)
	var y1 := 0.0
	var y2 := 0.0
	var w := TAU * hz / RATE
	var r := 0.985
	for j in int(RATE * 0.12):
		if i0 + j >= b.size():
			break
		var t := float(j) / RATE
		var x := rng.randf_range(-1.0, 1.0) * exp(-t * 900.0)
		var y := x + 2.0 * r * cos(w) * y1 - r * r * y2
		y2 = y1
		y1 = y
		b[i0 + j] += y * 0.08 * loud * exp(-t * decay)


# A ringing metal/ceramic ping: a few inharmonic partials.
static func _ping(b: PackedFloat32Array, at: float, hz: float, loud: float, decay: float) -> void:
	var i0 := int(at * RATE)
	for j in int(RATE * minf(5.0 / decay, 1.5)):
		if i0 + j >= b.size():
			break
		var t := float(j) / RATE
		var e := minf(t / 0.002, 1.0) * exp(-t * decay)
		b[i0 + j] += (sin(TAU * hz * t) + 0.5 * sin(TAU * hz * 2.76 * t) * exp(-t * decay) + 0.25 * sin(TAU * hz * 5.4 * t)) * e * loud


static func _chain(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _new(0.35)
	_tick(b, 0.0, 2400.0, 1.0, 60.0, rng)
	_tick(b, 0.09, 1900.0, 0.8, 70.0, rng)
	for k in 4:   # the little beads of the chain settling
		_ping(b, 0.11 + k * 0.035 + rng.randf() * 0.01, 3100.0 + rng.randf() * 600.0, 0.05, 60.0)
	return b


static func _lighter(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _new(0.45)
	_tick(b, 0.0, 3000.0, 0.9, 50.0, rng)    # the flint wheel
	_tick(b, 0.02, 2200.0, 0.5, 60.0, rng)
	# the flame catching: a soft low "fwump"
	var lp := 0.0
	for i in range(int(0.05 * RATE), b.size()):
		var t := float(i) / RATE - 0.05
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.06)
		b[i] += lp * 1.6 * minf(t / 0.03, 1.0) * exp(-t * 9.0)
	return b


static func _squish(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _new(0.6)
	var lp := 0.0
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.08)
		ph += TAU * (120.0 + 80.0 * sin(t * 31.0)) / RATE
		var env := minf(t / 0.04, 1.0) * exp(-t * 4.5)
		b[i] = (lp * 1.2 + sin(ph) * 0.25) * env * (0.6 + 0.4 * sin(t * 47.0))
	for k in 3:   # little wet bubbles
		_bubble(b, 0.08 + k * 0.13, 260.0 + k * 60.0, 0.35)
	return b


static func _bubble(b: PackedFloat32Array, at: float, hz: float, loud: float) -> void:
	var i0 := int(at * RATE)
	var ph := 0.0
	for j in int(RATE * 0.06):
		if i0 + j >= b.size():
			break
		var t := float(j) / RATE
		ph += TAU * hz * (1.0 + t * 14.0) / RATE   # a bubble's pitch rises as it pops
		b[i0 + j] += sin(ph) * loud * sin(minf(t / 0.06, 1.0) * PI)


static func _chew(rng: RandomNumberGenerator, gag: bool) -> PackedFloat32Array:
	var b := _new(1.5 if gag else 0.85)
	for k in 3:   # nom, nom, nom: a crunchy-wet bite each
		var at := k * 0.24
		var lp := 0.0
		for j in int(0.16 * RATE):
			var i := int(at * RATE) + j
			var t := float(j) / RATE
			lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.25)
			b[i] += lp * sin(t / 0.16 * PI) * (0.7 + 0.3 * rng.randf())
		_bubble(b, at + 0.05, 180.0, 0.2)
	if gag:   # "hurk": a throaty, voiced retch
		var ph := 0.0
		var lp2 := 0.0
		for j in int(0.55 * RATE):
			var i := int(0.8 * RATE) + j
			var t := float(j) / RATE
			ph += TAU * (115.0 - 30.0 * t + 6.0 * sin(t * 40.0)) / RATE
			lp2 = lerpf(lp2, rng.randf_range(-1.0, 1.0), 0.2)
			var voice := sin(ph) + 0.5 * sin(ph * 2.0) + 0.3 * sin(ph * 3.0)
			b[i] += (voice * 0.5 + lp2 * 0.6) * sin(minf(t / 0.55, 1.0) * PI) * 0.8
	return b


static func _clatter(rng: RandomNumberGenerator, count: int, pitch: float) -> PackedFloat32Array:
	var b := _new(0.7)
	for k in count:
		var at := rng.randf() * 0.35 + (0.0 if k == 0 else 0.03)
		_ping(b, at, (900.0 + rng.randf() * 900.0) * pitch, 0.12 + rng.randf() * 0.08, 28.0 + rng.randf() * 20.0)
		_tick(b, at, 2500.0, 0.3, 80.0, rng)
	return b


static func _pop(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _new(0.3)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += TAU * (650.0 - 900.0 * t) / RATE
		b[i] = sin(ph) * exp(-t * 28.0) * minf(t / 0.001, 1.0)
	_tick(b, 0.0, 1400.0, 1.4, 90.0, rng)
	return b


static func _creak(rng: RandomNumberGenerator, seconds: float, hz: float) -> PackedFloat32Array:
	var b := _new(seconds)
	var ph := 0.0
	var f := hz
	for i in b.size():
		var t := float(i) / RATE
		f = lerpf(f, hz * (0.8 + 0.5 * rng.randf()), 0.002)   # a wobbling, stick-slipping squeak
		ph += TAU * f / RATE
		var saw := fposmod(ph / TAU, 1.0) * 2.0 - 1.0
		var grit := 0.6 + 0.4 * sin(t * 90.0 + sin(t * 23.0) * 3.0)
		b[i] = saw * grit * sin(minf(t / seconds, 1.0) * PI) * 0.35
	return b


static func _latch(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _new(0.25)
	_tick(b, 0.0, 900.0, 1.6, 40.0, rng)    # the lid landing
	_tick(b, 0.05, 2600.0, 1.0, 70.0, rng)  # the latch clicking shut
	return b


static func _glug(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _new(1.3)
	for k in 6:
		_bubble(b, 0.05 + k * 0.19 + rng.randf() * 0.04, 140.0 + rng.randf() * 70.0, 0.5)
	var lp := 0.0
	for i in b.size():   # the trickle under it
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.15)
		b[i] += lp * 0.25 * sin(float(i) / b.size() * PI)
	return b


static func _squirt(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _new(0.55)
	var hp := 0.0
	var last := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := rng.randf_range(-1.0, 1.0)
		hp = n - last
		last = n
		var sputter := 0.55 + 0.45 * sin(t * 140.0 + sin(t * 37.0) * 4.0)
		b[i] = hp * 0.5 * sputter * minf(t / 0.02, 1.0) * exp(-t * 3.5)
	_bubble(b, 0.0, 300.0, 0.3)
	return b


static func _scribble(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _new(1.3)
	var bp1 := 0.0
	var bp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		bp1 = lerpf(bp1, rng.randf_range(-1.0, 1.0), 0.5)
		bp2 = lerpf(bp2, bp1, 0.5)
		var stroke := maxf(sin(t * TAU * 5.5 + sin(t * 9.0) * 2.0), 0.0)   # pen strokes back and forth
		b[i] = (bp1 - bp2) * stroke * 1.4 * minf((1.3 - t) / 0.1, 1.0)
	return b


static func _rush(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _new(2.2)
	_tick(b, 0.0, 2800.0, 0.8, 60.0, rng)   # the igniter
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.12)
		lp2 = lerpf(lp2, lp, 0.3)
		b[i] += lp2 * 1.5 * minf(t / 0.15, 1.0) * minf((2.2 - t) / 0.4, 1.0)
	return b


static func _ding() -> PackedFloat32Array:
	var b := _new(1.4)
	_ping(b, 0.0, 1320.0, 0.35, 3.2)
	return b


static func _thump(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _new(0.3)
	var ph := 0.0
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += TAU * (110.0 - 120.0 * t) / RATE
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.2)
		b[i] = (sin(ph) * 0.8 + lp * 0.6) * exp(-t * 18.0)   # soft thump, a little splat
	return b


static func _rustle(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _new(0.9)
	var hp := 0.0
	var last := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := rng.randf_range(-1.0, 1.0)
		hp = n - last
		last = n
		var crinkle := 1.0 if rng.randf() < 0.08 else 0.35   # paper bags crinkling
		b[i] = hp * 0.3 * crinkle * sin(minf(t / 0.9, 1.0) * PI)
	for k in 3:   # things rolling and knocking
		_ping(b, 0.1 + k * 0.2 + rng.randf() * 0.05, 500.0 + rng.randf() * 300.0, 0.08, 40.0)
	return b


static func _fuse(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _new(1.6)
	var hp := 0.0
	var last := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := rng.randf_range(-1.0, 1.0)
		hp = n - last
		last = n
		b[i] = hp * 0.35 * minf(t / 0.05, 1.0) * (0.8 + 0.2 * sin(t * 60.0))
		if rng.randf() < 0.004:   # sparks crackling
			b[i] += rng.randf_range(0.6, 1.0) * (1.0 if rng.randf() < 0.5 else -1.0)
	return b


static func _kaboom(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _new(2.6)
	var ph := 0.0
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += TAU * (30.0 + 70.0 * exp(-t * 7.0)) / RATE
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.18 * exp(-t * 1.5) + 0.02)
		lp2 = lerpf(lp2, lp, 0.25)
		var crack := rng.randf_range(-1.0, 1.0) * exp(-t * 40.0)
		b[i] = (sin(ph) * 1.1 * exp(-t * 2.2) + lp2 * 3.0 * exp(-t * 1.6) + crack * 0.8) * minf(t / 0.002, 1.0)
	for k in 10:   # debris pattering down
		_tick(b, 0.4 + rng.randf() * 1.6, 900.0 + rng.randf() * 1500.0, 0.6, 50.0, rng)
	return b


# Bees: many slightly different wingbeats (whole numbers of cycles a second, so the 2 s loop joins up), drifting
# louder and softer.
static func _buzz() -> PackedFloat32Array:
	var b := _new(2.0)
	var bees := [[210.0, 0.0], [224.0, 1.3], [236.0, 2.1], [198.0, 0.7], [251.0, 2.9], [217.0, 4.1], [243.0, 5.3]]
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in bees.size():
			var f: float = bees[k][0]
			var ph: float = bees[k][1]
			var saw := 2.0 * fmod(t * f + ph, 1.0) - 1.0
			var amp := 0.55 + 0.45 * sin(TAU * (0.5 + k * 0.5) * t + ph)
			v += saw * amp
		b[i] = v / bees.size()
	return b


static func _wav(buf: PackedFloat32Array, peak_to: float, looped := false) -> AudioStreamWAV:
	var peak := 0.0001
	for v in buf:
		peak = maxf(peak, absf(v))
	var n := buf.size()
	var fade := mini(int(RATE * 0.02), n / 4)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var g := peak_to / peak
		if i > n - fade and not looped:
			g *= float(n - i) / fade
		data.encode_s16(i * 2, int(clampf(buf[i] * g, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav
