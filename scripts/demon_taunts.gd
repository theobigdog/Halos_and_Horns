# Demon taunts (Ted's wife's list, Nov 25): deep, goofy-spooky, cartoon-menace voices and whistles,
# all synthesized here (no samples, no recordings, no imitation of any character).
#
# How the voice works: a band-limited sawtooth "vocal cord" buzz, roughened per glottal cycle (rasp =
# pitch/loudness jitter, sub = every other cycle louder, which adds a growly half-pitch undertone), goes
# through three formant resonators (the vowel: ah, oh, ee...) set ~8% low for a big demon throat, plus
# a low "chest" path so the fundamental stays fat. Consonants are faked: "h" is noise through the vowel's
# formants, "m"/"n" are hummed nasal formants that open into the vowel. Whistles are a pure tone with a
# breathy band of noise around it. Everything then gets a slapback echo and a small room reverb, a DC
# filter, and a loudness match (gentle tanh saturation) with the peak at -3 dBFS.
#
# Callers cache the result: make() takes about a tenth of a second per sound.
extends RefCounted

const RATE := 22050

# key -> label shown on screen (the signature isn't in here)
const TAUNTS := {
	"laugh": "Mwahahahahaaa!",
	"whistle": "Fweet-fweeet! Over here!",
	"nyah": "Nyah nyah nyah nyah nyah nyah!",
	"wolf_whistle": "Wheet-wheeooo~",
	"over_here": "Ooover heeere!",
}
const SIGNATURE_LABEL := "MWA-HA! Grrrr..."

# Vowel formants for a deep male voice: [F1, F2, F3 Hz, loudness]. M and N are nasal hums.
const VOWELS := {
	"AH": [700.0, 1100.0, 2400.0, 1.0],
	"AE": [640.0, 1650.0, 2350.0, 1.0],
	"EH": [510.0, 1700.0, 2400.0, 0.95],
	"EE": [290.0, 2100.0, 2850.0, 0.8],
	"OH": [520.0, 820.0, 2350.0, 0.95],
	"OO": [320.0, 800.0, 2200.0, 0.8],
	"UH": [580.0, 1150.0, 2350.0, 0.9],
	"ER": [460.0, 1250.0, 1600.0, 0.85],
	"M": [240.0, 1000.0, 2200.0, 0.3],
	"N": [260.0, 1500.0, 2400.0, 0.3],
}
const BANDWIDTH := [90.0, 110.0, 160.0]
const FORMANT_GAIN := [1.0, 0.55, 0.3]
const TRACT := 0.92            # formant scale: < 1 = a bigger throat
const TAIL := 0.45             # seconds of echo after the last sound
const TARGET_LOUDNESS := 0.2   # gated RMS (above ~150 Hz) relative to the peak, before the -3 dB scale
const PEAK := 0.708            # -3 dBFS

const DEMON := {"rasp": 0.35, "sub": 0.25, "breath": 0.03, "vib": 0.015}


static func make(key: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6660 + key.length() * 31   # fixed: the same sound every time
	var buf: PackedFloat32Array
	match key:
		"laugh":
			buf = _laugh(rng)
		"whistle":
			buf = _over_here_whistle(rng)
		"nyah":
			buf = _nyah(rng)
		"wolf_whistle":
			buf = _wolf_whistle(rng)
		"over_here":
			buf = _over_here(rng)
		_:
			if key != "signature":
				push_warning("demon_taunts: unknown taunt '%s', using the signature" % key)
			buf = _signature(rng)
	return _finish(buf)


# ---------- the taunts ----------

# A long "MWAHAHAHA" that speeds up, climbs and gets louder, then a big wobbly "HAAAA" that sinks.
static func _laugh(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := _buffer(2.58)
	_sing(buf, rng, _with(DEMON, {"t": 0.0, "dur": 0.42, "amp": 0.75, "attack": 0.04, "release": 0.07,
			"pitch": [[0.0, 82.0], [0.35, 98.0], [1.0, 112.0]],
			"vowel": [[0.0, "M"], [0.3, "M"], [0.45, "OO"], [0.62, "AH"], [1.0, "AH"]]}))
	var t := 0.5
	var count := 7
	for k in count:
		var x := float(k) / (count - 1)
		var f := lerpf(100.0, 158.0, x)
		_sing(buf, rng, _with(DEMON, {"t": t, "dur": lerpf(0.15, 0.125, x), "h": 0.035,
				"amp": lerpf(0.55, 0.95, x), "attack": 0.012, "release": 0.04,
				"pitch": [[0.0, f * 1.05], [1.0, f * 0.9]],
				"vowel": [[0.0, "AH"], [0.7, "AH"], [1.0, "UH"]]}))
		t += lerpf(0.2, 0.15, x)
	_sing(buf, rng, _with(DEMON, {"t": t, "dur": 0.85, "h": 0.05, "amp": 1.0, "attack": 0.02,
			"release": 0.28, "rasp": 0.45, "sub": 0.35, "vib": 0.045,
			"pitch": [[0.0, 168.0], [0.12, 192.0], [0.45, 178.0], [1.0, 90.0]],
			"vowel": [[0.0, "AH"], [0.7, "AH"], [1.0, "OH"]]}))
	return buf


# A sharp two-note "hey, over here!" whistle: a quick upward flick, then a longer one that holds and dips.
static func _over_here_whistle(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := _buffer(0.72)
	_whistle(buf, rng, 0.02, 0.17, [[0.0, 880.0], [0.45, 1320.0], [1.0, 1360.0]], 0.85)
	_whistle(buf, rng, 0.27, 0.43, [[0.0, 980.0], [0.22, 1390.0], [0.7, 1360.0], [1.0, 1140.0]], 1.0)
	return buf


# The playground chant, sol-sol-mi-la-sol-mi, sung "nyah" in a deep, nasal, sneering demon voice.
static func _nyah(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sol := 123.5   # B2
	var mi := 103.8    # G#2
	var la := 138.6    # C#3
	var notes := [[sol, 0.17, 0.8], [sol, 0.23, 0.9], [mi, 0.3, 0.85], [la, 0.18, 0.9], [sol, 0.23, 0.85], [mi, 0.5, 1.0]]
	var total := 0.0
	for nt in notes:
		total += nt[1]
	var buf := _buffer(total + 0.02)
	var t := 0.02
	for k in notes.size():
		var f: float = notes[k][0]
		var len_s: float = notes[k][1]
		var dur := len_s * 0.88
		var last := k == notes.size() - 1
		var pitch := [[0.0, f * 0.93], [0.08 / dur, f], [1.0, f * (0.9 if last else 0.99)]]
		_sing(buf, rng, _with(DEMON, {"t": t, "dur": dur, "amp": notes[k][2], "attack": 0.015,
				"release": 0.12 if last else 0.04, "vib": 0.035 if last else 0.01, "rasp": 0.3,
				"pitch": pitch,
				"vowel": [[0.0, "N"], [0.035 / dur, "N"], [0.06 / dur, "EE"], [0.11 / dur, "AE"], [1.0, "AH"]]}))
		t += len_s
	return buf


# A low cat-call: a rising "wheet", then a "wheeooo" that leaps up and slides way down.
static func _wolf_whistle(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := _buffer(1.19)
	_whistle(buf, rng, 0.02, 0.38, [[0.0, 430.0], [0.15, 410.0], [1.0, 1050.0]], 0.85)
	_whistle(buf, rng, 0.47, 0.72, [[0.0, 560.0], [0.17, 1080.0], [0.33, 1065.0], [1.0, 330.0]], 1.0)
	return buf


# A cheeky sing-song call-out, "Ooo-ver heeeere!" (our own: just the vowels and the cadence).
static func _over_here(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := _buffer(1.6)
	_sing(buf, rng, _with(DEMON, {"t": 0.0, "dur": 0.42, "amp": 0.85, "attack": 0.05, "release": 0.05,
			"pitch": [[0.0, 112.0], [0.35, 140.0], [1.0, 150.0]],
			"vowel": [[0.0, "OO"], [0.25, "OH"], [1.0, "OH"]]}))
	_sing(buf, rng, _with(DEMON, {"t": 0.44, "dur": 0.24, "amp": 0.7, "attack": 0.02, "release": 0.04,
			"pitch": [[0.0, 128.0], [1.0, 118.0]],
			"vowel": [[0.0, "OO"], [0.2, "UH"], [0.6, "ER"], [1.0, "ER"]]}))
	_sing(buf, rng, _with(DEMON, {"t": 0.74, "dur": 0.85, "h": 0.06, "amp": 1.0, "attack": 0.03,
			"release": 0.22, "vib": 0.05,
			"pitch": [[0.0, 130.0], [0.25, 176.0], [0.6, 166.0], [1.0, 116.0]],
			"vowel": [[0.0, "EE"], [0.55, "EE"], [0.8, "ER"], [1.0, "ER"]]}))
	return buf


# The signature: a short, punchy "MWA-HA!" that drops into a rumbling growl.
static func _signature(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := _buffer(1.34)
	_sing(buf, rng, _with(DEMON, {"t": 0.0, "dur": 0.3, "amp": 0.8, "attack": 0.03, "release": 0.05,
			"pitch": [[0.0, 95.0], [0.4, 128.0], [1.0, 138.0]],
			"vowel": [[0.0, "M"], [0.3, "M"], [0.5, "OO"], [0.7, "AH"], [1.0, "AH"]]}))
	_sing(buf, rng, _with(DEMON, {"t": 0.36, "dur": 0.34, "h": 0.04, "amp": 1.0, "attack": 0.01,
			"release": 0.08, "rasp": 0.4,
			"pitch": [[0.0, 175.0], [0.2, 184.0], [1.0, 140.0]],
			"vowel": [[0.0, "AH"], [1.0, "AH"]]}))
	_sing(buf, rng, _with(DEMON, {"t": 0.72, "dur": 0.62, "amp": 0.95, "attack": 0.05, "release": 0.25,
			"rasp": 0.9, "sub": 0.6, "growl": 0.7, "breath": 0.06,
			"pitch": [[0.0, 72.0], [0.5, 78.0], [1.0, 62.0]],
			"vowel": [[0.0, "UH"], [0.4, "ER"], [1.0, "OO"]]}))
	_rumble(buf, rng, 0.7, 0.66, 0.6)
	return buf


# ---------- synthesis ----------

static func _buffer(seconds: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(int((seconds + TAIL) * RATE))
	return buf


static func _with(base: Dictionary, extra: Dictionary) -> Dictionary:
	var d := base.duplicate()
	d.merge(extra, true)
	return d


# A smooth (cosine-eased) curve through [[u, value], ...] points, u from 0 to 1.
static func _curve(points: Array, u: float) -> float:
	if u <= points[0][0]:
		return points[0][1]
	for k in range(1, points.size()):
		var u1: float = points[k][0]
		if u <= u1:
			var u0: float = points[k - 1][0]
			var x := (u - u0) / maxf(u1 - u0, 0.0001)
			return lerpf(points[k - 1][1], points[k][1], 0.5 - 0.5 * cos(x * PI))
	return points[points.size() - 1][1]


# The formants of a vowel path [[u, "AH"], ...] at u: [F1, F2, F3, loudness].
static func _vowel_at(path: Array, u: float) -> Array:
	var a: Array = VOWELS[path[0][1]]
	if u <= path[0][0]:
		return a
	for k in range(1, path.size()):
		var u1: float = path[k][0]
		if u <= u1:
			var u0: float = path[k - 1][0]
			var x := (u - u0) / maxf(u1 - u0, 0.0001)
			var p: Array = VOWELS[path[k - 1][1]]
			var q: Array = VOWELS[path[k][1]]
			return [lerpf(p[0], q[0], x), lerpf(p[1], q[1], x), lerpf(p[2], q[2], x), lerpf(p[3], q[3], x)]
	return VOWELS[path[path.size() - 1][1]]


# Band-limiting correction for the sawtooth's jump (polyBLEP): no aliasing fizz.
static func _blep(ph: float, dt: float) -> float:
	if ph < dt:
		var x := ph / dt
		return x + x - x * x - 1.0
	if ph > 1.0 - dt:
		var x := (ph - 1.0) / dt
		return x * x + x + x + 1.0
	return 0.0


# One voiced syllable mixed into buf. p: t, dur (s), pitch [[u, Hz]], vowel [[u, name]], amp,
# attack, release (s), h (s of breathy "h" before the voice), rasp, sub, growl, breath, vib.
static func _sing(buf: PackedFloat32Array, rng: RandomNumberGenerator, p: Dictionary) -> void:
	var t0: float = p["t"]
	var dur: float = p["dur"]
	var pitch: Array = p["pitch"]
	var vowel: Array = p.get("vowel", [[0.0, "AH"]])
	var amp: float = p.get("amp", 1.0)
	var attack: float = p.get("attack", 0.02)
	var release: float = p.get("release", 0.06)
	var h: float = p.get("h", 0.0)
	var rasp: float = p.get("rasp", 0.0)
	var sub: float = p.get("sub", 0.0)
	var growl: float = p.get("growl", 0.0)
	var breath: float = p.get("breath", 0.02)
	var vib: float = p.get("vib", 0.0)
	var i0 := int(t0 * RATE)
	var n := int(dur * RATE)
	var voice_start := h * 0.6
	var ph := rng.randf()
	var cyc_f := 1.0
	var cyc_a := 1.0
	var alt := 1.0
	var gph := 0.0
	var body := 0.0
	var body_k := 1.0 - exp(-TAU * 300.0 / RATE)
	var warm := 0.0
	var warm_k := 1.0 - exp(-TAU * 3500.0 / RATE)
	# three band-pass resonators: coefficients b0 (= -b2), a1, a2 and states x1, x2, y1, y2
	var co := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0])
	var st := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	var vgain := 1.0
	for j in n:
		var idx := i0 + j
		if idx >= buf.size():
			break
		var u := float(j) / n
		var t := float(j) / RATE
		if j % 16 == 0:
			var fm := _vowel_at(vowel, u)
			vgain = fm[3]
			for k in 3:
				var fc: float = minf(fm[k] * TRACT, RATE * 0.45)
				var w0 := TAU * fc / RATE
				var bw: float = BANDWIDTH[k]
				var alpha := sin(w0) * bw / (2.0 * fc)
				var a0 := 1.0 + alpha
				co[k * 3] = alpha / a0
				co[k * 3 + 1] = -2.0 * cos(w0) / a0
				co[k * 3 + 2] = (1.0 - alpha) / a0
		var f := _curve(pitch, u)
		f *= 1.0 + vib * sin(TAU * 5.3 * t) * minf(t / 0.15, 1.0)
		var dt := f * cyc_f / RATE
		ph += dt
		if ph >= 1.0:
			ph -= 1.0
			cyc_f = 1.0 + rasp * 0.03 * rng.randf_range(-1.0, 1.0)
			cyc_a = 1.0 + rasp * 0.35 * rng.randf_range(-1.0, 1.0)
			alt = -alt
		var src := (2.0 * ph - 1.0 - _blep(ph, dt)) * cyc_a * (1.0 + sub * alt)
		if growl > 0.0:   # a throaty flutter, about 30 times a second, never quite regular
			gph += TAU * (30.0 + 6.0 * rng.randf_range(-1.0, 1.0)) / RATE
			src *= 1.0 - growl * (0.5 + 0.5 * sin(gph))
		warm += (src - warm) * warm_k
		src = warm
		# envelopes: voice fades in after the "h", fades out at the end
		var tv := t - voice_start
		var venv := 0.0
		if tv > 0.0:
			venv = sin(minf(tv / attack, 1.0) * PI * 0.5)
		venv *= sin(clampf((dur - t) / release, 0.0, 1.0) * PI * 0.5)
		var nenv := breath * venv
		if h > 0.0:
			var hx := 0.0
			if t < h:
				hx = minf(t / 0.012, 1.0)
			else:
				hx = maxf(0.0, 1.0 - (t - h) / 0.03)
			nenv += 0.7 * hx * minf((dur - t) / 0.01, 1.0)
		var x := src * venv + rng.randf_range(-1.0, 1.0) * nenv
		var y := 0.0
		for k in 3:
			var s := k * 4
			var yk := co[k * 3] * (x - st[s + 1]) - co[k * 3 + 1] * st[s + 2] - co[k * 3 + 2] * st[s + 3]
			st[s + 1] = st[s]
			st[s] = x
			st[s + 3] = st[s + 2]
			st[s + 2] = yk
			y += yk * FORMANT_GAIN[k]
		body += (src * venv - body) * body_k
		buf[idx] += (y * vgain * 1.6 + body * 0.55) * amp
	return


# A whistle note: a pure tone with a hint of 2nd harmonic, breath around it and a little "chiff" onset.
static func _whistle(buf: PackedFloat32Array, rng: RandomNumberGenerator, t0: float, dur: float,
		pitch: Array, amp: float) -> void:
	var i0 := int(t0 * RATE)
	var n := int(dur * RATE)
	var ph := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var c1 := 0.0
	var c2 := 0.0
	for j in n:
		var idx := i0 + j
		if idx >= buf.size():
			break
		var u := float(j) / n
		var t := float(j) / RATE
		var f := _curve(pitch, u) * (1.0 + 0.006 * sin(TAU * 6.0 * t))
		ph += TAU * f / RATE
		var env := sin(minf(t / 0.015, 1.0) * PI * 0.5) * sin(clampf((dur - t) / 0.06, 0.0, 1.0) * PI * 0.5)
		# breath: noise through a resonator that follows the whistle's pitch
		var w0 := TAU * f / RATE
		var alpha := sin(w0) / (2.0 * 6.0)
		var a0 := 1.0 + alpha
		var wn := rng.randf_range(-1.0, 1.0)
		var y := (alpha * (wn - c2) + 2.0 * cos(w0) * b1 - (1.0 - alpha) * b2) / a0
		c2 = c1
		c1 = wn
		b2 = b1
		b1 = y
		var chiff := rng.randf_range(-1.0, 1.0) * 0.25 * exp(-t * 90.0)
		var tone := sin(ph) + 0.05 * sin(2.0 * ph)
		buf[idx] += (tone * 0.8 + y * 0.6 + chiff) * env * amp
	return


# A deep rumble under the growl: heavily smoothed noise.
static func _rumble(buf: PackedFloat32Array, rng: RandomNumberGenerator, t0: float, dur: float, amp: float) -> void:
	var i0 := int(t0 * RATE)
	var n := int(dur * RATE)
	var a := 0.0
	var b := 0.0
	for j in n:
		var idx := i0 + j
		if idx >= buf.size():
			break
		var t := float(j) / RATE
		a = lerpf(a, rng.randf_range(-1.0, 1.0), 0.03)
		b = lerpf(b, a, 0.04)
		var env := minf(t / 0.08, 1.0) * pow(1.0 - float(j) / n, 1.5)
		buf[idx] += b * 6.0 * env * amp
	return


# ---------- finishing: echo, room, clean-up, loudness ----------

static func _finish(dry: PackedFloat32Array) -> AudioStreamWAV:
	var n := dry.size()
	var out := PackedFloat32Array()
	out.resize(n)
	# a slapback echo (a demon shouting in a crypt), darkened each repeat
	var echo := PackedFloat32Array()
	echo.resize(n)
	var d := int(0.17 * RATE)
	var lp := 0.0
	for i in n:
		var fb := 0.0
		if i >= d:
			fb = dry[i - d] + echo[i - d] * 0.35
		lp += (fb - lp) * 0.35
		echo[i] = lp
	# a small room: four combs into two all-passes (Schroeder)
	var combs := [int(0.0297 * RATE), int(0.0371 * RATE), int(0.0411 * RATE), int(0.0437 * RATE)]
	var room := PackedFloat32Array()
	room.resize(n)
	for c in combs:
		var line := PackedFloat32Array()
		line.resize(c)
		var pos := 0
		var damp := 0.0
		for i in n:
			var o := line[pos]
			damp += (o - damp) * 0.45
			line[pos] = dry[i] + damp * 0.72
			pos = (pos + 1) % c
			room[i] += o * 0.25
	for ap in [int(0.005 * RATE), int(0.0017 * RATE)]:
		var line2 := PackedFloat32Array()
		line2.resize(ap)
		var pos2 := 0
		for i in n:
			var v := line2[pos2]
			var inp := room[i]
			var w := inp + v * 0.5
			line2[pos2] = w
			room[i] = v - w * 0.5
			pos2 = (pos2 + 1) % ap
	# mix + DC blocker (~20 Hz high-pass)
	var x1 := 0.0
	var y1 := 0.0
	for i in n:
		var s := dry[i] + echo[i] * 0.28 + room[i] * 0.22
		y1 = s - x1 + 0.9943 * y1
		x1 = s
		out[i] = y1
	# fade the very ends to exact silence
	for i in mini(int(0.004 * RATE), n):
		out[i] *= float(i) / (0.004 * RATE)
	var fade := int(0.08 * RATE)
	for i in mini(fade, n):
		out[n - 1 - i] *= float(i) / fade
	# peak to 1, then saturate gently (tanh) until the loudness matches, or turn down if it's already louder
	var peak := 0.0
	for v in out:
		peak = maxf(peak, absf(v))
	if peak > 0.0:
		for i in n:
			out[i] /= peak
	var drive := 1.0
	var l0 := loudness(out)
	if l0 < TARGET_LOUDNESS:
		var lo := 1.0
		var hi := 4.0
		for it in 14:
			var mid := (lo + hi) * 0.5
			if loudness(_saturate(out, mid)) < TARGET_LOUDNESS:
				lo = mid
			else:
				hi = mid
		drive = (lo + hi) * 0.5
		out = _saturate(out, drive)
	var gain := PEAK * minf(1.0, TARGET_LOUDNESS / maxf(l0, 0.0001)) if drive == 1.0 else PEAK
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(roundf(clampf(out[i] * gain, -1.0, 1.0) * 32767.0)))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav


static func _saturate(buf: PackedFloat32Array, drive: float) -> PackedFloat32Array:
	var out := buf.duplicate()
	var norm := 1.0 / tanh(drive)
	for i in out.size():
		out[i] = tanh(out[i] * drive) * norm
	return out


# Rough loudness: RMS of the 50 ms windows that are within 30 dB of the loudest one, measured after a
# 150 Hz high-pass (ears hear the deep end less).
static func loudness(buf: PackedFloat32Array) -> float:
	var win := int(0.05 * RATE)
	var powers := PackedFloat32Array()
	var hp := 0.0
	var prev := 0.0
	var k := exp(-TAU * 150.0 / RATE)
	var acc := 0.0
	var count := 0
	for i in buf.size():
		hp = k * (hp + buf[i] - prev)
		prev = buf[i]
		acc += hp * hp
		count += 1
		if count == win:
			powers.append(acc / win)
			acc = 0.0
			count = 0
	var top := 0.0
	for pw in powers:
		top = maxf(top, pw)
	var sum := 0.0
	var used := 0
	for pw in powers:
		if pw >= top * 0.001:
			sum += pw
			used += 1
	return sqrt(sum / maxi(used, 1))
