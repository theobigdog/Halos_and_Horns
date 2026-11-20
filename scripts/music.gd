# Halos & Horns music: composed right here as note patterns and synthesized in code
# (no samples, no audio files), so every note is our own. Goofy-spooky: a cartoon
# haunted house with a theremin, a music box, a wheezy organ, a choir of "aah"s,
# plucked strings and a few drums.
#
# Rendering a song in GDScript takes a few seconds, so it happens once, in a
# background thread, and the result is cached in user://music_cache/ (each song is
# rebuilt only when VERSION changes). Until a song is ready, that part is silent.
#
# How to write a song (see SONGS at the bottom):
#   "bpm", "beats" per bar (3 = waltz), "steps" per beat (2 = eighth notes), "bars".
#   Each part has an instrument, a volume, a pan (-1 left .. 1 right) and "bars":
#   one string per bar, repeated in order to fill the song. Each space-separated
#   token is one step:  c4 = a note (also f#3, bb2),  d4+f4+a4 = a chord,
#   - = keep holding,  . = rest,  a "!" on the end = accent, a "'" = soft.
#   Drum letters: k kick, s snare, h hat, o open hat, x shaker, b tick, w tock, t tom, c clap.
extends Node

const RATE := 22050
const BUS := "Music"
const CACHE_DIR := "user://music_cache"
const VERSION := 1                 # bump after changing any song or instrument
const TABLE := 1024                # wavetable size (one cycle)
const FADE_SPEED := 0.8            # crossfade: share of full volume per second
const STING_DUCK := 0.25           # the music drops to this while a win/lose sting plays

var enabled := true
var _streams := {}                 # song name -> AudioStreamWAV, once rendered
var _queued := {}                  # song name -> true while waiting or rendering
var _queue: Array = []
var _task := -1                    # WorkerThreadPool task id while a song renders
var _want := ""                    # the song that should be playing
var _players: Array = []           # two players for crossfading
var _levels := [0.0, 0.0]
var _active := 0
var _names := ["", ""]
var _sting: AudioStreamPlayer
var _duck := 1.0


func _ready() -> void:
	setup_bus()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	_sting = AudioStreamPlayer.new()
	_sting.bus = BUS
	add_child(_sting)
	# Headless (tests, servers): no speakers, so don't spend seconds rendering.
	enabled = DisplayServer.get_name() != "headless"
	if enabled:
		prepare(["lobby", "hiding", "hunt", "win", "lose", "shuffle", "tango", "bones"])


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


static func setup_bus() -> void:
	if AudioServer.get_bus_index(BUS) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, BUS)
	AudioServer.set_bus_send(idx, "Master")
	var lowpass := AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = 7500.0
	AudioServer.add_bus_effect(idx, lowpass)
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.7
	reverb.damping = 0.5
	reverb.spread = 1.0
	reverb.wet = 0.2
	reverb.dry = 0.9
	AudioServer.add_bus_effect(idx, reverb)


# 0 = off, 1 = full. (Saved in settings by main.)
static func set_volume(linear: float) -> void:
	setup_bus()
	var idx := AudioServer.get_bus_index(BUS)
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))


# ---------- playing ----------

# Crossfade to this song ("" = silence). Safe to call every frame.
func play(song: String) -> void:
	if song == _want:
		return
	_want = song
	if song != "" and not _streams.has(song):
		prepare([song])
		return
	_switch()


# A one-shot (win / lose): the music ducks under it.
func sting(song: String) -> void:
	if _streams.has(song):
		_sting.stream = _streams[song]
		_sting.play()


func _switch() -> void:
	if _names[_active] == _want:
		return
	_active = 1 - _active
	var p: AudioStreamPlayer = _players[_active]
	_names[_active] = _want
	if _want == "":
		p.stop()
		return
	p.stream = _streams[_want]
	p.play()
	_levels[_active] = 0.0


func _process(delta: float) -> void:
	var duck_target := STING_DUCK if _sting.playing else 1.0
	_duck = move_toward(_duck, duck_target, delta * 2.0)
	for i in 2:
		var p: AudioStreamPlayer = _players[i]
		var target := 1.0 if (i == _active and _names[i] != "") else 0.0
		_levels[i] = move_toward(_levels[i], target, delta * FADE_SPEED)
		p.volume_db = linear_to_db(maxf(_levels[i] * _duck, 0.0001))
		if target == 0.0 and _levels[i] <= 0.0 and p.playing:
			p.stop()
			_names[i] = ""


# ---------- rendering in the background, with a cache ----------

func prepare(songs: Array) -> void:
	for s in songs:
		if _streams.has(s) or _queued.has(s) or not SONGS.has(s):
			continue
		_queued[s] = true
		_queue.append(s)
	_next()


func is_ready(song: String) -> bool:
	return _streams.has(song)


func _next() -> void:
	if _task != -1 or _queue.is_empty():
		return
	var song: String = _queue.pop_front()
	var cached := _load_cache(song)
	if cached:
		_done(song, cached, false)
		return
	_task = WorkerThreadPool.add_task(_render_task.bind(song), false, "music: " + song)


func _render_task(song: String) -> void:
	var wav := render(SONGS[song])
	call_deferred("_finished", song, wav)


func _finished(song: String, wav: AudioStreamWAV) -> void:
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_done(song, wav, true)


func _done(song: String, wav: AudioStreamWAV, save: bool) -> void:
	_streams[song] = wav
	_queued.erase(song)
	if save:
		_save_cache(song, wav)
	if song == _want:
		_switch()
	_next()


static func _cache_path(song: String) -> String:
	return "%s/%s_v%d.wav" % [CACHE_DIR, song, VERSION]


func _load_cache(song: String) -> AudioStreamWAV:
	var path := _cache_path(song)
	if not FileAccess.file_exists(path):
		return null
	var wav := AudioStreamWAV.load_from_file(path)
	if wav == null or wav.data.size() < 4:
		return null
	_set_loop(wav, SONGS[song])
	return wav


func _save_cache(song: String, wav: AudioStreamWAV) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	wav.save_to_wav(_cache_path(song))


static func _set_loop(wav: AudioStreamWAV, song: Dictionary) -> void:
	if song.get("loop", true):
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.data.size() / 4    # 16-bit stereo = 4 bytes a frame
	else:
		wav.loop_mode = AudioStreamWAV.LOOP_DISABLED


# ---------- the synthesizer ----------

# Turn a song into a stereo AudioStreamWAV. Pure math, so it can run on any thread.
# A looping song is exactly its bars long, and note tails that run past the end
# wrap around to the start, so the loop is seamless.
static func render(song: Dictionary) -> AudioStreamWAV:
	var bpm: float = song["bpm"]
	var spb: int = song.get("steps", 2)
	var bar_steps: int = int(song.get("beats", 4)) * spb
	var bars: int = song["bars"]
	var step_sec := 60.0 / bpm / spb
	var looping: bool = song.get("loop", true)
	var frames := int(round(bars * bar_steps * step_sec * RATE))
	var n := frames if looping else frames + int(RATE * 2.5)
	var left := PackedFloat32Array()
	left.resize(n)
	var right := PackedFloat32Array()
	right.resize(n)
	var tables := _make_tables()
	var rng := RandomNumberGenerator.new()
	rng.seed = 666
	for part in song["parts"]:
		var vol: float = part.get("vol", 0.5)
		var pan: float = part.get("pan", 0.0)
		var gl := vol * sqrt(0.5 * (1.0 - pan))
		var gr := vol * sqrt(0.5 * (1.0 + pan))
		var events := _parse_part(part, bars, bar_steps)
		if part.get("legato", false):
			var buf := _legato(part, events, n, step_sec, tables)
			for i in n:
				left[i] += buf[i] * gl
				right[i] += buf[i] * gr
			continue
		for e in events:
			var start := int(round(e[0] * step_sec * RATE))
			var dur: float = e[1] * step_sec
			for pitch in e[2]:
				var note := _note(part["inst"], pitch, dur, e[3], tables, rng)
				var count := note.size()
				for j in count:
					var k := start + j
					if k >= n:
						if not looping:
							break
						k -= n
						if k >= n:
							break
					left[k] += note[j] * gl
					right[k] += note[j] * gr
	# Even out the loudness: scale the peak to 1, then a gentle cubic soft clip
	# (squeezes the loudest bits a little, so the quiet parts come up).
	# Songs are matched by average loudness (so the quiet sneaky one isn't much
	# softer than the chase), but never pushed so hard the peaks get squashed.
	var peak := 0.0
	var power := 0.0
	for i in n:
		peak = maxf(peak, maxf(absf(left[i]), absf(right[i])))
		power += left[i] * left[i] + right[i] * right[i]
	var rms := sqrt(power / (2 * n))
	var gain := minf(0.24 / rms, 1.3 / peak) if peak > 0.0 else 1.0
	var data := PackedByteArray()
	data.resize(n * 4)
	for i in n:
		var l := clampf(left[i] * gain, -1.0, 1.0)
		var r := clampf(right[i] * gain, -1.0, 1.0)
		l = l * (1.5 - 0.5 * l * l)
		r = r * (1.5 - 0.5 * r * r)
		data.encode_s16(i * 4, int(l * 0.85 * 32767.0))
		data.encode_s16(i * 4 + 2, int(r * 0.85 * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = true
	wav.data = data
	_set_loop(wav, song)
	return wav


# Bars of tokens -> [[step, length in steps, [pitches or drum letters], velocity], ...]
static func _parse_part(part: Dictionary, bars: int, bar_steps: int) -> Array:
	var events := []
	var src: Array = part["bars"]
	var drums: bool = part["inst"] == "drums"
	var shift: int = 12 * int(part.get("oct", 0))
	var last := -1
	for b in bars:
		var tokens := (src[b % src.size()] as String).split(" ", false)
		for s in bar_steps:
			var tok: String = tokens[s] if s < tokens.size() else "."
			var step := b * bar_steps + s
			if tok == "-":
				if last >= 0:
					events[last][1] += 1
				continue
			if tok == ".":
				last = -1
				continue
			var vel := 0.75
			if tok.ends_with("!"):
				vel = 1.0
				tok = tok.trim_suffix("!")
			elif tok.ends_with("'"):
				vel = 0.45
				tok = tok.trim_suffix("'")
			var pitches := []
			for p in tok.split("+", false):
				pitches.append(p if drums else _midi(p) + shift)
			events.append([step, 1, pitches, vel])
			last = events.size() - 1
	return events


const NOTE_NAMES := {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}


static func _midi(tok: String) -> int:
	var pc: int = NOTE_NAMES.get(tok[0], 0)
	var i := 1
	if i < tok.length() and tok[i] == "#":
		pc += 1
		i += 1
	elif i < tok.length() - 1 and tok[i] == "b":
		pc -= 1
		i += 1
	return 12 * (int(tok.substr(i)) + 1) + pc


static func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


# One cycle of each sound, as a sum of harmonics: [harmonic number, loudness].
static func _make_tables() -> Dictionary:
	var shapes := {
		"sine": [[1, 1.0]],
		# a wheezy little pump organ: a few drawbars
		"organ": [[1, 1.0], [2, 0.55], [3, 0.2], [4, 0.3], [6, 0.12], [8, 0.1]],
		# "aah": a strong low end with the 2nd-4th harmonics up (vowel-ish)
		"choir": [[1, 0.8], [2, 0.7], [3, 0.55], [4, 0.35], [5, 0.18], [6, 0.1], [7, 0.06]],
		# the theremin: nearly a sine, with a touch of buzz
		"theremin": [[1, 1.0], [2, 0.12], [3, 0.06]],
	}
	var out := {}
	for key in shapes:
		var t := PackedFloat32Array()
		t.resize(TABLE)
		var peak := 0.0
		for i in TABLE:
			var x := TAU * i / TABLE
			var s := 0.0
			for h in shapes[key]:
				s += sin(x * h[0]) * h[1]
			t[i] = s
			peak = maxf(peak, absf(s))
		for i in TABLE:
			t[i] /= peak
		out[key] = t
	return out


# A wavetable voice: a soft attack, sustain, a release, a little vibrato, and
# `voices` copies spread by `spread` cents for a fuller, chorused sound.
static func _pad(table: PackedFloat32Array, sine: PackedFloat32Array, hz: float, dur: float,
		attack: float, release: float, vib_rate: float, vib_depth: float, voices: int, spread: float) -> PackedFloat32Array:
	var hold := int(dur * RATE)
	var rel := int(release * RATE)
	var n := hold + rel
	var out := PackedFloat32Array()
	out.resize(n)
	var att := maxi(int(attack * RATE), 1)
	var vib_step := vib_rate * TABLE / RATE
	for v in voices:
		var cents := 0.0 if voices == 1 else lerpf(-spread, spread, float(v) / (voices - 1))
		var step := hz * pow(2.0, cents / 1200.0) * TABLE / RATE
		var phase := float(v * 337 % TABLE)
		var vphase := float(v * 211 % TABLE)
		var g := 1.0 / voices
		for i in n:
			var env := 1.0
			if i < att:
				env = float(i) / att
			if i >= hold:
				env *= 1.0 - float(i - hold) / rel
			vphase += vib_step
			if vphase >= TABLE:
				vphase -= TABLE
			phase += step * (1.0 + vib_depth * sine[int(vphase)])
			while phase >= TABLE:
				phase -= TABLE
			out[i] += table[int(phase)] * env * g
	return out


# One note (or drum hit) as a mono buffer.
static func _note(inst: String, pitch, dur: float, vel: float, tables: Dictionary, rng: RandomNumberGenerator) -> PackedFloat32Array:
	match inst:
		"organ":
			return _scaled(_pad(tables["organ"], tables["sine"], _hz(pitch), dur * 0.92, 0.012, 0.09, 6.0, 0.003, 2, 4.0), vel)
		"choir":
			return _scaled(_pad(tables["choir"], tables["sine"], _hz(pitch), dur, 0.3, 0.6, 5.2, 0.006, 3, 10.0), vel)
		"box":
			return _music_box(tables["sine"], _hz(pitch), vel)
		"pizz":
			return _pluck(_hz(pitch), 0.35, 0.993, vel, rng, 0.6)
		"bass":
			return _pluck(_hz(pitch), maxf(dur, 0.25) + 0.2, 0.9985, vel, rng, 0.3)
		"drums":
			return _drum(pitch, vel, rng)
	return PackedFloat32Array()


static func _scaled(buf: PackedFloat32Array, vel: float) -> PackedFloat32Array:
	for i in buf.size():
		buf[i] *= vel
	return buf


# A tinkly music box tine: a pure tone plus a quick, bright inharmonic "ting".
static func _music_box(sine: PackedFloat32Array, hz: float, vel: float) -> PackedFloat32Array:
	var n := int(1.6 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var s1 := hz * TABLE / RATE
	var s2 := hz * 5.4 * TABLE / RATE
	var p1 := 0.0
	var p2 := 0.0
	var d1 := exp(-3.2 / RATE)
	var d2 := exp(-14.0 / RATE)
	var e1 := vel
	var e2 := vel * 0.35
	for i in n:
		p1 += s1
		p2 += s2
		while p1 >= TABLE:
			p1 -= TABLE
		while p2 >= TABLE:
			p2 -= TABLE
		out[i] = sine[int(p1)] * e1 + sine[int(p2)] * e2
		e1 *= d1
		e2 *= d2
	# a tiny fade-in so it doesn't click
	for i in mini(40, n):
		out[i] *= i / 40.0
	return out


# A plucked string (Karplus-Strong): a burst of noise ringing in a short delay line.
# brightness 0..1 = how much of the pick's "click" survives.
static func _pluck(hz: float, seconds: float, decay: float, vel: float, rng: RandomNumberGenerator, brightness: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var period := maxi(int(RATE / hz), 2)
	var line := PackedFloat32Array()
	line.resize(period)
	var prev := 0.0
	for i in period:
		var x := rng.randf_range(-1.0, 1.0)
		prev = lerpf(prev, x, brightness)   # softer pick = smoother starting noise
		line[i] = prev
	var idx := 0
	var last := 0.0
	for i in n:
		var cur := line[idx]
		var avg := (cur + last) * 0.5 * decay
		last = cur
		line[idx] = avg
		idx += 1
		if idx >= period:
			idx = 0
		out[i] = cur * vel
	var fade := mini(int(0.05 * RATE), n)
	for i in fade:
		out[n - 1 - i] *= float(i) / fade
	return out


static func _drum(kind: String, vel: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var len_s := {"k": 0.35, "s": 0.22, "h": 0.06, "o": 0.3, "x": 0.08, "b": 0.05, "w": 0.06, "t": 0.45, "c": 0.2}
	var n := int(len_s.get(kind, 0.1) * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var hp_prev := 0.0
	var hp_out := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		hp_out = 0.6 * (hp_out + noise - hp_prev)   # crude high-pass: a hiss
		hp_prev = noise
		var s := 0.0
		match kind:
			"k":
				phase += TAU * (45.0 + 110.0 * exp(-t * 32.0)) / RATE
				s = sin(phase) * exp(-t * 9.0) + noise * 0.15 * exp(-t * 200.0)
			"s":
				phase += TAU * 185.0 / RATE
				s = sin(phase) * 0.45 * exp(-t * 25.0) + hp_out * 0.6 * exp(-t * 18.0)
			"h":
				s = hp_out * 0.35 * exp(-t * 70.0)
			"o":
				s = hp_out * 0.3 * exp(-t * 10.0)
			"x":
				s = hp_out * 0.28 * minf(t / 0.012, 1.0) * exp(-t * 40.0)
			"b":
				phase += TAU * 1650.0 / RATE
				s = sin(phase) * 0.5 * exp(-t * 90.0)
			"w":
				phase += TAU * 1000.0 / RATE
				s = sin(phase) * 0.5 * exp(-t * 70.0)
			"t":
				phase += TAU * (75.0 + 45.0 * exp(-t * 12.0)) / RATE
				s = sin(phase) * 0.8 * exp(-t * 7.0)
			"c":
				# three quick slaps, then a short ring
				var env := 0.0
				if t < 0.035:
					env = 1.0 if fmod(t, 0.011) < 0.006 else 0.2
				else:
					env = exp(-(t - 0.035) * 22.0)
				s = hp_out * 0.5 * env
		out[i] = s * vel
	return out


# The theremin: one continuous voice that glides from note to note, with a wide,
# wobbly vibrato. Rendered across the whole song in one go.
static func _legato(part: Dictionary, events: Array, n: int, step_sec: float, tables: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var table: PackedFloat32Array = tables["theremin"]
	var sine: PackedFloat32Array = tables["sine"]
	var step_frames := step_sec * RATE
	# What to aim for at each step: [hz, velocity], or none.
	var total := int(round(n / step_frames)) + 1
	var target_hz := PackedFloat32Array()
	target_hz.resize(total)
	var target_vel := PackedFloat32Array()
	target_vel.resize(total)
	var first_hz := 0.0
	for e in events:
		for s in e[1]:
			var k: int = e[0] + s
			if k < total:
				target_hz[k] = _hz(e[2][0])
				target_vel[k] = e[3]
		if first_hz == 0.0:
			first_hz = _hz(e[2][0])
	var glide := exp(-1.0 / (0.07 * RATE))      # ~70 ms swoop between notes
	var attack := exp(-1.0 / (0.04 * RATE))
	var release := exp(-1.0 / (0.12 * RATE))
	var vib_step := 5.6 * TABLE / RATE
	var hz := first_hz
	var amp := 0.0
	var phase := 0.0
	var vphase := 0.0
	var depth: float = part.get("vibrato", 0.012)
	for i in n:
		var k := mini(int(i / step_frames), total - 1)
		var th := target_hz[k]
		var tv := target_vel[k]
		if th > 0.0:
			hz = th + (hz - th) * glide
			amp = tv + (amp - tv) * attack
		else:
			amp *= release
		vphase += vib_step
		if vphase >= TABLE:
			vphase -= TABLE
		# the vibrato swells in over each held note
		phase += hz * (1.0 + depth * minf(amp, 1.0) * sine[int(vphase)]) * TABLE / RATE
		while phase >= TABLE:
			phase -= TABLE
		out[i] = table[int(phase)] * amp
	return out


# ---------- the songs (all original) ----------

const SONGS := {
	# Menus and lobby: "The Possessed Waltz". D minor, 3/4. The theremin sings,
	# the strings go oom-pah-pah, and the music box joins the second time round.
	"lobby": {
		"bpm": 150, "beats": 3, "steps": 2, "bars": 16,
		"parts": [
			{"inst": "theremin", "legato": true, "vol": 0.42, "pan": 0.1, "vibrato": 0.014, "bars": [
				"a4 - - - d5 -", "f5 - - - e5 -", "d5 - - - g5 -", "e5 - - - c#5 -",
				"d5 - - - a4 -", "bb4 - - - d5 -", "g4 - bb4 - d5 -", "c#5 - - - - -",
				"a4 - - - d5 -", "f5 - - - a5 -", "g5 - f5 - e5 -", "d5 - - - bb4 -",
				"f5 - - - d5 -", "e5 - g5 - c#5 -", "d5 - - - - -", ". . e5 - c#5 -"]},
			{"inst": "bass", "vol": 0.55, "pan": -0.15, "bars": [
				"d2 - . . . .", "a1 - . . . .", "g1 - . . . .", "a1 - . . . .",
				"d2 - . . . .", "bb1 - . . . .", "g1 - . . . .", "a1 - . . e2 .",
				"d2 - . . . .", "a1 - . . . .", "g1 - . . . .", "d2 - . . . .",
				"bb1 - . . . .", "a1 - . . . .", "d2 - . . . .", "a1 - . . c#2 ."]},
			{"inst": "pizz", "vol": 0.3, "pan": -0.35, "bars": [
				". . d3+f3+a3 . d3+f3+a3 .", ". . d3+f3+a3 . d3+f3+a3 .", ". . d3+g3+bb3 . d3+g3+bb3 .", ". . c#3+e3+g3 . c#3+e3+a3 .",
				". . d3+f3+a3 . d3+f3+a3 .", ". . d3+f3+bb3 . d3+f3+bb3 .", ". . d3+g3+bb3 . d3+g3+bb3 .", ". . c#3+e3+a3 . c#3+e3+g3 .",
				". . d3+f3+a3 . d3+f3+a3 .", ". . d3+f3+a3 . d3+f3+a3 .", ". . d3+g3+bb3 . d3+g3+bb3 .", ". . d3+g3+bb3 . d3+g3+bb3 .",
				". . d3+f3+bb3 . d3+f3+bb3 .", ". . c#3+e3+a3 . c#3+e3+g3 .", ". . d3+f3+a3 . d3+f3+a3 .", ". . c#3+e3+a3 . c#3+e3+g3 ."]},
			{"inst": "box", "vol": 0.22, "pan": 0.45, "bars": [
				"", "", "", "", "", "", "", "",
				"d6 a5 f5 a5 d6 a5", "f6 d6 a5 d6 f6 d6", "g6 d6 bb5 d6 g6 d6", "bb5 g5 d5 g5 bb5 g5",
				"bb5 f5 d5 f5 bb5 f5", "a5 e5 c#5 e5 g5 e5", "f5 d5 a4 d5 f5 a5", "e5 c#5 a4 c#5 e5 g5"]},
			{"inst": "choir", "vol": 0.16, "pan": 0.0, "bars": [
				"", "", "", "", "", "", "", "",
				"d4+f4+a4 - - - - -", "d4+f4+a4 - - - - -", "d4+g4+bb4 - - - - -", "d4+g4+bb4 - - - - -",
				"d4+f4+bb4 - - - - -", "c#4+e4+a4 - - - - -", "d4+f4+a4 - - - - -", "c#4+e4+a4 - - - - -"]},
			{"inst": "drums", "vol": 0.3, "bars": ["k . x' . x' .", "k . x' . x' .", "k . x' . x' .", "k . x' . x x'"]},
		]},

	# The hiding countdown: tiptoeing about. E minor, a ticking clock, sneaky plucks.
	"hiding": {
		"bpm": 112, "beats": 4, "steps": 2, "bars": 16,
		"parts": [
			{"inst": "pizz", "vol": 0.5, "pan": 0.2, "bars": [
				"e4 . . g4 . . f#4 .", "e4 . b3 . . . . .", "e4 . . g4 . . a4 .", "b4 . . . a#4 . . .",
				"c5 . . b4 . . a4 .", "g4 . f#4 . e4 . . .", "d#4 . . f#4 . . b3 .", "e4 . . . . . e4' g4'"]},
			{"inst": "box", "vol": 0.18, "pan": -0.4, "bars": [
				"", "", "", "", "", "", "", "",
				"e5 . . g5 . . f#5 .", "e5 . b4 . . . . .", "e5 . . g5 . . a5 .", "b5 . . . a#5 . . .",
				"c6 . . b5 . . a5 .", "g5 . f#5 . e5 . . .", "d#5 . . f#5 . . b4 .", "e5 . . . . . . ."]},
			{"inst": "bass", "vol": 0.5, "pan": -0.1, "bars": [
				"e2 . . . b1 . . .", "e2 . . . b1 . . .", "a1 . . . e2 . . .", "b1 . . . f#2 . . .",
				"a1 . . . e2 . . .", "e2 . . . b1 . . .", "b1 . . . f#2 . . .", "e2 . . . b1 . . ."]},
			{"inst": "organ", "vol": 0.1, "pan": 0.0, "bars": [
				"e3+b3 - - - - - - -", "e3+b3 - - - - - - -", "a3+e4 - - - - - - -", "b3+f#4 - - - - - - -",
				"a3+e4 - - - - - - -", "e3+b3 - - - - - - -", "b3+d#4 - - - - - - -", "e3+b3 - - - - - - -"]},
			{"inst": "drums", "vol": 0.32, "bars": ["b . w . b . w .", "b . w . b . w .", "b . w . b . w .", "b . w . b . w . "]},
		]},

	# The hunt: a galloping chase with organ, choir stabs and drums. D minor.
	"hunt": {
		"bpm": 150, "beats": 4, "steps": 2, "bars": 16,
		"parts": [
			{"inst": "organ", "vol": 0.36, "pan": 0.15, "bars": [
				"d5 . a4 . f5 e5 d5 .", "c#5 d5 e5 . a4 . . .", "d5 . bb4 . f5 e5 d5 .", "e5 . c5 . g5 f5 e5 .",
				"f5 . d5 . a5 g5 f5 .", "e5 f5 g5 . a5 . . .", "bb5 a5 g5 . d5 . g5 .", "a5 - - - c#5 - e5 -",
				"d5 . a4 . f5 e5 d5 .", "c5 . a4 . f5 e5 c5 .", "d5 . bb4 . g5 f5 d5 .", "e5 . c#5 . a5 g5 e5 .",
				"f5 - d5 - bb4 - d5 -", "e5 - c5 - g4 - c5 -", "c#5 d5 e5 f5 g5 f5 e5 c#5", "a5 - - - - - . ."]},
			{"inst": "bass", "vol": 0.55, "pan": -0.1, "bars": [
				"d2 d2 d3 d2 d2 d2 d3 d2", "d2 d2 d3 d2 d2 d2 d3 d2", "bb1 bb1 bb2 bb1 bb1 bb1 bb2 bb1", "c2 c2 c3 c2 c2 c2 c3 c2",
				"d2 d2 d3 d2 d2 d2 d3 d2", "d2 d2 d3 d2 d2 d2 d3 d2", "g1 g1 g2 g1 g1 g1 g2 g1", "a1 a1 a2 a1 a1 a1 a2 a1",
				"d2 d2 d3 d2 d2 d2 d3 d2", "f1 f1 f2 f1 f1 f1 f2 f1", "g1 g1 g2 g1 g1 g1 g2 g1", "a1 a1 a2 a1 a1 a1 a2 a1",
				"bb1 bb1 bb2 bb1 bb1 bb1 bb2 bb1", "c2 c2 c3 c2 c2 c2 c3 c2", "a1 a1 a2 a1 a1 a1 a2 a1", "a1 a1 a2 a1 a1! . a1! ."]},
			{"inst": "choir", "vol": 0.22, "pan": -0.2, "bars": [
				"d4+f4+a4 - - . . . . .", ". . . . . . . .", "d4+f4+bb4 - - . . . . .", "e4+g4+c5 - - . . . . .",
				"d4+f4+a4 - - . . . . .", ". . . . . . . .", "d4+g4+bb4 - - . . . . .", "c#4+e4+a4 - - - - - - -",
				"d4+f4+a4 - - . . . . .", "c4+f4+a4 - - . . . . .", "d4+g4+bb4 - - . . . . .", "c#4+e4+a4 - - . . . . .",
				"d4+f4+bb4 - - - - - - -", "e4+g4+c5 - - - - - - -", "c#4+e4+a4 - - - - - - -", "c#4+e4+g4+a4 - - - - - . ."]},
			{"inst": "box", "vol": 0.14, "pan": 0.5, "bars": [
				"", "", "", "", "", "", "", "",
				"a6 . . . . . . .", ". . . . a6 . . .", "bb6 . . . . . . .", ". . . . a6 . . .",
				"f6 . . . . . . .", "g6 . . . . . . .", "e6 . . . . . . .", "c#6 . . . . . . ."]},
			{"inst": "drums", "vol": 0.42, "bars": [
				"k! h s h k k s h", "k h s h k k s o", "k! h s h k k s h", "k h s h k k s o",
				"k! h s h k k s h", "k h s h k k s o", "k! h s h k k s h", "k h s h t t t t",
				"k! h s h k k s h", "k h s h k k s o", "k! h s h k k s h", "k h s h k k s o",
				"k! h s h k k s h", "k h s h k k s o", "k! h s h k k s h", "s s s s k! . k! ."]},
		]},

	# Round themes (Ted, Nov 19: three more in the spirit of the waltz, picked at random each round
	# and played during the hunt until maps get their own music).

	# "The Graveyard Shuffle": G minor, a swinging wheezy organ over a walking bass and offbeat plucks.
	"shuffle": {
		"bpm": 128, "beats": 4, "steps": 2, "bars": 16,
		"parts": [
			{"inst": "organ", "vol": 0.34, "pan": 0.15, "bars": [
				"g4 . bb4 . d5 - c5 bb4", "a4 - g4 - f#4 - d4 .", "g4 . bb4 . d5 - eb5 d5", "c5 - - - . . . .", "eb5 . d5 . c5 . bb4 .", "a4 . c5 . bb4 - a4 .", "g4 . f#4 . g4 . a4 .", "d4 - - - . . d5 c5", "bb4 . d5 . g5 - f5 eb5", "d5 - c5 - bb4 - a4 .", "bb4 . d5 . g5 - a5 bb5", "a5 - - - f#5 - - .", "g5 . f5 . eb5 . d5 .", "c5 . eb5 . d5 - c5 .", "bb4 . a4 . g4 . f#4 .", "g4 - - - . . . ."]},
			{"inst": "bass", "vol": 0.55, "pan": -0.15, "bars": [
				"g2 . bb2 . d3 . bb2 .", "d2 . f#2 . a2 . f#2 .", "g2 . bb2 . d3 . bb2 .", "c2 . eb2 . g2 . eb2 .", "c2 . eb2 . g2 . eb2 .", "d2 . f#2 . a2 . f#2 .", "g2 . bb2 . d3 . bb2 .", "d2 . f#2 . a2 . f#2 .", "g2 . bb2 . d3 . bb2 .", "d2 . f#2 . a2 . f#2 .", "g2 . bb2 . d3 . bb2 .", "d2 . f#2 . a2 . f#2 .", "c2 . eb2 . g2 . eb2 .", "c2 . eb2 . g2 . eb2 .", "d2 . f#2 . a2 . f#2 .", "g2 . bb2 . d3 . bb2 ."]},
			{"inst": "pizz", "vol": 0.26, "pan": -0.4, "bars": [
				". g3+bb3+d4 . g3+bb3+d4 . g3+bb3+d4 . g3+bb3+d4", ". d3+f#3+a3 . d3+f#3+a3 . d3+f#3+a3 . d3+f#3+a3", ". g3+bb3+d4 . g3+bb3+d4 . g3+bb3+d4 . g3+bb3+d4", ". c3+eb3+g3 . c3+eb3+g3 . c3+eb3+g3 . c3+eb3+g3", ". c3+eb3+g3 . c3+eb3+g3 . c3+eb3+g3 . c3+eb3+g3", ". d3+f#3+a3 . d3+f#3+a3 . d3+f#3+a3 . d3+f#3+a3", ". g3+bb3+d4 . g3+bb3+d4 . g3+bb3+d4 . g3+bb3+d4", ". d3+f#3+a3 . d3+f#3+a3 . d3+f#3+a3 . d3+f#3+a3", ". g3+bb3+d4 . g3+bb3+d4 . g3+bb3+d4 . g3+bb3+d4", ". d3+f#3+a3 . d3+f#3+a3 . d3+f#3+a3 . d3+f#3+a3", ". g3+bb3+d4 . g3+bb3+d4 . g3+bb3+d4 . g3+bb3+d4", ". d3+f#3+a3 . d3+f#3+a3 . d3+f#3+a3 . d3+f#3+a3", ". c3+eb3+g3 . c3+eb3+g3 . c3+eb3+g3 . c3+eb3+g3", ". c3+eb3+g3 . c3+eb3+g3 . c3+eb3+g3 . c3+eb3+g3", ". d3+f#3+a3 . d3+f#3+a3 . d3+f#3+a3 . d3+f#3+a3", ". g3+bb3+d4 . g3+bb3+d4 . g3+bb3+d4 . g3+bb3+d4"]},
			{"inst": "choir", "vol": 0.14, "pan": 0.0, "bars": [
				"", "", "", "", "", "", "", "", "g3+bb3+d4 - - - - - - -", "f#3+a3+d4 - - - - - - -", "g3+bb3+d4 - - - - - - -", "f#3+a3+d4 - - - - - - -", "g3+c4+eb4 - - - - - - -", "g3+c4+eb4 - - - - - - -", "f#3+a3+d4 - - - - - - -", "g3+bb3+d4 - - - - - - -"]},
			{"inst": "box", "vol": 0.16, "pan": 0.5, "bars": [
				"", "", "", "", "", "", "", "", "g6 . . . . . . .", ". . . . a6 . . .", "bb6 . . . . . . .", ". . . . f#6 . . .", "eb6 . . . . . . .", "c6 . . . . . . .", "d6 . . . . . . .", "g6 . . . . . . ."]},
			{"inst": "drums", "vol": 0.34, "bars": ["k . h' s . k h s", "k . h' s . k h s", "k . h' s . k h s", "k . h' s k . s s"]},
		]},

	# "Phantom Tango": A minor. The theremin croons over a tango bass, stabbing strings and a choir.
	"tango": {
		"bpm": 112, "beats": 4, "steps": 2, "bars": 16,
		"parts": [
			{"inst": "theremin", "legato": true, "vol": 0.4, "pan": 0.1, "vibrato": 0.018, "bars": [
				"e5 - - - - - d5 c5", "b4 - - - a4 - - -", "e5 - - - - - f5 e5", "d#5 - - - - - - -", "d5 - - - - - c5 b4", "a4 - - - g#4 - - -", "a4 - b4 - c5 - d5 -", "e5 - - - - - - -", "a5 - - - - - g5 f5", "e5 - - - - - d5 c5", "d5 - - - - - c5 b4", "c5 - - - b4 - - -", "a4 - - - c5 - e5 -", "f5 - - - e5 - d5 -", "e5 - - - g#4 - b4 -", "a4 - - - - - - -"]},
			{"inst": "bass", "vol": 0.55, "pan": -0.1, "bars": [
				"a1 - - a1 c2 . e2 .", "a1 - - a1 c2 . e2 .", "a1 - - a1 c2 . e2 .", "e1 - - e1 g#1 . b1 .", "d2 - - d2 f2 . a2 .", "e1 - - e1 g#1 . b1 .", "a1 - - a1 c2 . e2 .", "e1 - - e1 g#1 . b1 .", "f1 - - f1 a1 . c2 .", "a1 - - a1 c2 . e2 .", "d2 - - d2 f2 . a2 .", "a1 - - a1 c2 . e2 .", "a1 - - a1 c2 . e2 .", "d2 - - d2 f2 . a2 .", "e1 - - e1 g#1 . b1 .", "a1 - - a1 c2 . e2 ."]},
			{"inst": "pizz", "vol": 0.3, "pan": -0.35, "bars": [
				"a3+c4+e4 . . . a3+c4+e4 . a3+c4+e4' .", "a3+c4+e4 . . . a3+c4+e4 . a3+c4+e4' .", "a3+c4+e4 . . . a3+c4+e4 . a3+c4+e4' .", "g#3+b3+e4 . . . g#3+b3+e4 . g#3+b3+e4' .", "a3+d4+f4 . . . a3+d4+f4 . a3+d4+f4' .", "g#3+b3+e4 . . . g#3+b3+e4 . g#3+b3+e4' .", "a3+c4+e4 . . . a3+c4+e4 . a3+c4+e4' .", "g#3+b3+e4 . . . g#3+b3+e4 . g#3+b3+e4' .", "a3+c4+f4 . . . a3+c4+f4 . a3+c4+f4' .", "a3+c4+e4 . . . a3+c4+e4 . a3+c4+e4' .", "a3+d4+f4 . . . a3+d4+f4 . a3+d4+f4' .", "a3+c4+e4 . . . a3+c4+e4 . a3+c4+e4' .", "a3+c4+e4 . . . a3+c4+e4 . a3+c4+e4' .", "a3+d4+f4 . . . a3+d4+f4 . a3+d4+f4' .", "g#3+b3+e4 . . . g#3+b3+e4 . g#3+b3+e4' .", "a3+c4+e4 . . . a3+c4+e4 . a3+c4+e4' ."]},
			{"inst": "choir", "vol": 0.15, "pan": 0.0, "bars": [
				"", "", "", "", "", "", "", "", "a3+c4+f4 - - - - - - -", "a3+c4+e4 - - - - - - -", "a3+d4+f4 - - - - - - -", "a3+c4+e4 - - - - - - -", "a3+c4+e4 - - - - - - -", "a3+d4+f4 - - - - - - -", "g#3+b3+e4 - - - - - - -", "a3+c4+e4 - - - - - - -"]},
			{"inst": "box", "vol": 0.15, "pan": 0.45, "bars": [
				"", "", "", "", "", "", "", "", "a6 e6 c6 e6 a6 . . .", ". . . . . . . .", "f6 d6 a5 d6 f6 . . .", ". . . . . . . .", "e6 c6 a5 c6 e6 . . .", ". . . . . . . .", "e6 b5 g#5 b5 e6 . . .", ". . . . . . . ."]},
			{"inst": "drums", "vol": 0.34, "bars": ["k . . k s . . .", "k . . k s . . .", "k . . k s . . .", "k . . k s . c c"]},
		]},

	# "Dance of the Bones": an E minor jig (6/8). A rattling music-box lead, oom-pa bass, a clap on two.
	"bones": {
		"bpm": 116, "beats": 2, "steps": 3, "bars": 32,
		"parts": [
			{"inst": "box", "vol": 0.3, "pan": 0.2, "bars": [
				"e5 . g5 b5 . g5", "a5 . f#5 d5 . f#5", "e5 . g5 b5 . e6", "d#6 . b5 f#5 . .", "e5 . g5 b5 . g5", "c6 . a5 e5 . g5", "g5 . e5 d#5 . f#5", "e5 . . e5 . .", "b5 . c6 b5 a5 g5", "a5 . b5 a5 g5 f#5", "g5 . a5 g5 f#5 e5", "d#5 . e5 f#5 . .", "b5 . c6 b5 a5 g5", "a5 . f#5 d6 . c6", "b5 . g5 f#5 . d#5", "e5 . . e5 . ."]},
			{"inst": "pizz", "vol": 0.42, "pan": -0.2, "bars": [
				". . e3+g3+b3 . . e3+g3+b3", ". . d3+f#3+a3 . . d3+f#3+a3", ". . e3+g3+b3 . . e3+g3+b3", ". . d#3+f#3+b3 . . d#3+f#3+b3", ". . e3+g3+b3 . . e3+g3+b3", ". . c3+e3+g3 . . c3+e3+g3", ". . e3+g3+b3 . . e3+g3+b3", ". . e3+g3+b3 . . e3+g3+b3", ". . e3+g3+b3 . . e3+g3+b3", ". . d3+f#3+a3 . . d3+f#3+a3", ". . e3+g3+b3 . . e3+g3+b3", ". . d#3+f#3+b3 . . d#3+f#3+b3", ". . e3+g3+b3 . . e3+g3+b3", ". . d3+f#3+a3 . . d3+f#3+a3", ". . d#3+f#3+b3 . . d#3+f#3+b3", ". . e3+g3+b3 . . e3+g3+b3"]},
			{"inst": "bass", "vol": 0.52, "pan": -0.1, "bars": [
				"e2 . . b1 . .", "d2 . . a1 . .", "e2 . . b1 . .", "b1 . . f#2 . .", "e2 . . b1 . .", "c2 . . g1 . .", "e2 . . b1 . .", "e2 . . b1 . .", "e2 . . b1 . .", "d2 . . a1 . .", "e2 . . b1 . .", "b1 . . f#2 . .", "e2 . . b1 . .", "d2 . . a1 . .", "b1 . . f#2 . .", "e2 . . b1 . ."]},
			{"inst": "organ", "vol": 0.12, "pan": 0.3, "bars": [
				"", "", "", "", "", "", "", "", "e3+b3 - - - - -", "d3+a3 - - - - -", "e3+b3 - - - - -", "b2+f#3 - - - - -", "e3+b3 - - - - -", "d3+a3 - - - - -", "b2+f#3 - - - - -", "e3+b3 - - - - -"]},
			{"inst": "choir", "vol": 0.13, "pan": 0.0, "bars": [
				"", "", "", "", "", "", "", "", "e4+g4+b4 - - - - -", "d4+f#4+a4 - - - - -", "e4+g4+b4 - - - - -", "d#4+f#4+b4 - - - - -", "e4+g4+b4 - - - - -", "d4+f#4+a4 - - - - -", "d#4+f#4+b4 - - - - -", "e4+g4+b4 - - - - -"]},
			{"inst": "drums", "vol": 0.34, "bars": ["k . x c . x", "k . x c . x", "k . x c . x", "k . x c c c"]},
		]},

	# Your side won: a bright little fanfare in D major.
	"win": {
		"bpm": 140, "beats": 4, "steps": 2, "bars": 2, "loop": false,
		"parts": [
			{"inst": "organ", "vol": 0.45, "bars": ["d5 f#5 a5 d6 - - . .", "a5+d6+f#6 - - - - - - -"]},
			{"inst": "choir", "vol": 0.3, "bars": [". . . . d4+f#4+a4 - - -", "d4+f#4+a4+d5 - - - - - - -"]},
			{"inst": "box", "vol": 0.25, "bars": [". . . . . . . .", "d6 f#6 a6 d7 . . . ."]},
			{"inst": "drums", "vol": 0.4, "bars": ["k . . . s s s s", "k! . . . . . . ."]},
		]},

	# Your side lost: a droopy, wobbly theremin "aww".
	"lose": {
		"bpm": 120, "beats": 4, "steps": 2, "bars": 2, "loop": false,
		"parts": [
			{"inst": "theremin", "legato": true, "vol": 0.5, "vibrato": 0.03, "bars": ["a4 - g4 - eb4 - - -", "d4 - - - - - . ."]},
			{"inst": "bass", "vol": 0.45, "bars": ["d2 . . . . . . .", "d1 . . . . . . ."]},
			{"inst": "drums", "vol": 0.3, "bars": [". . . . . . . .", "t . . . . . . ."]},
		]},
}
