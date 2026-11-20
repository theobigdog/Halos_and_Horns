# Placeholder sound effects, generated in code so there are no audio files yet.
# Warm, soft tones: detuned sine pairs, slow fade-ins, low-passed "air", and
# everything runs through a reverb + low-pass bus (see setup_bus).
# These get replaced by real recorded sounds later.
extends RefCounted

const RATE := 22050
const BUS := "SFX"


# Creates the SFX audio bus: a low-pass filter to remove harsh highs, then
# reverb so sounds feel like they're in a space instead of right in your ear.
static func setup_bus() -> void:
	if AudioServer.get_bus_index(BUS) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, BUS)
	AudioServer.set_bus_send(idx, "Master")
	var lowpass := AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = 3200.0
	AudioServer.add_bus_effect(idx, lowpass)
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.55
	reverb.damping = 0.65
	reverb.spread = 0.8
	reverb.wet = 0.22
	reverb.dry = 0.85
	AudioServer.add_bus_effect(idx, reverb)


# partials: [[Hz, loudness], ...]. Each partial is doubled with a copy detuned by
# `detune_cents`, which beats gently against it - that's what makes it warm.
# attack: fade-in seconds (longer = softer start, no click or "pop").
# air: soft low-passed noise mixed in (a breathy whoosh). glide: pitch at the end
# relative to the start.
static func tone(partials: Array, seconds: float, volume: float, attack: float,
		detune_cents := 7.0, air := 0.0, glide := 1.0) -> AudioStreamWAV:
	var n := int(RATE * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phases := []
	for k in partials.size() * 2:
		phases.append(randf() * TAU)   # random start phases: no identical clicky starts
	var detune := pow(2.0, detune_cents / 1200.0)
	var noise := 0.0
	var noise2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := float(i) / n
		# Smooth (sine-shaped) fade-in, then a gentle curved fade-out to exact silence.
		var env := sin(minf(t / attack, 1.0) * PI * 0.5)
		env *= pow(1.0 - u, 1.6)
		var bend := lerpf(1.0, glide, u)
		var s := 0.0
		for k in partials.size():
			var f: float = partials[k][0] * bend
			phases[k * 2] += TAU * f / RATE
			phases[k * 2 + 1] += TAU * f * detune / RATE
			s += (sin(phases[k * 2]) + sin(phases[k * 2 + 1])) * 0.5 * partials[k][1]
		if air > 0.0:
			# Two-stage smoothing makes the noise a soft "fff", not a hiss.
			noise = lerpf(noise, randf_range(-1.0, 1.0), 0.05)
			noise2 = lerpf(noise2, noise, 0.05)
			s += noise2 * air * 12.0
		data.encode_s16(i * 2, int(clampf(s * env * volume, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav


# Each blessing type has its own throw sound. All quiet, soft-edged, and low-ish:
# the harsh feel before came from loud high partials and instant starts.
static func throw_sound(kind: String) -> AudioStreamWAV:
	match kind:
		"holy_light":     # soft airy shimmer
			return tone([[784.0, 0.5], [1175.0, 0.2]], 0.45, 0.09, 0.06, 8.0, 0.25, 1.02)
		"blessed_water":  # gentle rising "bloop"
			return tone([[392.0, 0.6], [588.0, 0.2]], 0.35, 0.11, 0.03, 10.0, 0.1, 1.35)
		"halo_ring":      # warm ring, like a soft bowl
			return tone([[659.0, 0.45], [988.0, 0.3]], 0.6, 0.08, 0.04, 5.0)
		"feather":        # mostly breath, a whisper of tone
			return tone([[440.0, 0.12]], 0.4, 0.1, 0.08, 4.0, 0.6, 0.85)
		"choir":          # tiny soft "aah" chord
			return tone([[392.0, 0.35], [494.0, 0.3], [587.0, 0.3]], 0.55, 0.11, 0.09, 9.0, 0.08)
	return tone([[784.0, 1.0]], 0.4, 0.08, 0.05)


static func hit_sound() -> AudioStreamWAV:
	# soft bell "tink" - still clear enough to notice
	return tone([[1046.0, 0.5], [1568.0, 0.25]], 0.5, 0.12, 0.008, 4.0)


static func caught_sound() -> AudioStreamWAV:
	# warm rising chord swell
	return tone([[392.0, 0.35], [494.0, 0.3], [587.0, 0.3], [784.0, 0.15]], 1.2, 0.12, 0.12, 8.0, 0.05, 1.12)


# A redeemed demon blowing up: a sharp crack into a deep, rolling rumble. (Its own random numbers:
# never the game's shared ones.)
static func boom_sound() -> AudioStreamWAV:
	var seconds := 1.6
	var n := int(RATE * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var low := 0.0
	var low2 := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := float(i) / n
		var white := rng.randf_range(-1.0, 1.0)
		low = lerpf(low, white, 0.04)          # rumble: heavily smoothed noise
		low2 = lerpf(low2, low, 0.06)
		ph += TAU * lerpf(70.0, 32.0, u) / RATE   # a falling thump underneath
		var crack := white * exp(-t * 40.0) * 0.6
		var rumble := low2 * 9.0 * exp(-t * 2.2)
		var thump := sin(ph) * exp(-t * 4.0) * 0.8
		var s := (crack + rumble + thump) * minf(t / 0.004, 1.0) * pow(1.0 - u, 0.8)
		data.encode_s16(i * 2, int(clampf(s * 0.75, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav


# Hit as a demon (Ted, Nov 20: "I don't know when I'm hit"): an unmistakable yelp of distress, a
# rising squeal that breaks and drops, rough in the throat. (Its own random numbers.)
static func distress_sound() -> AudioStreamWAV:
	var seconds := 0.55
	var n := int(RATE * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var ph := 0.0
	var grit := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := float(i) / n
		# pitch: up fast, then it cracks and drops
		var f := 520.0 + 680.0 * sin(minf(u / 0.35, 1.0) * PI * 0.5) if u < 0.35 else lerpf(1200.0, 380.0, (u - 0.35) / 0.65)
		f *= 1.0 + 0.04 * sin(t * TAU * 28.0)
		ph += TAU * f / RATE
		grit = lerpf(grit, rng.randf_range(-1.0, 1.0), 0.3)
		var wave := sin(ph) * 0.6 + sin(ph * 2.0) * 0.25 + sin(ph * 3.0) * 0.12
		var s := (wave * (1.0 + grit * 0.5) + grit * 0.15) * minf(t / 0.01, 1.0) * pow(1.0 - u, 1.3)
		data.encode_s16(i * 2, int(clampf(s * 0.7, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav


static func possess_sound() -> AudioStreamWAV:
	# low, smooth demonic "whumm"
	return tone([[98.0, 0.7], [147.0, 0.3]], 0.5, 0.22, 0.04, 12.0, 0.35, 0.75)


# Flying (demons): an eerie musical-saw wail (Ted, Nov 18), swooping up and down with a wide wobbly
# vibrato, over faint wing whooshes. The pitch curve and the vibrato both repeat exactly once per loop,
# and the wave's phase is nudged to end on a whole cycle, so it loops seamlessly.
static func fly_loop() -> AudioStreamWAV:
	var seconds := 2.5
	var n := int(RATE * seconds)
	var center := 560.0                # Hz: the saw's middle note
	var steps := PackedFloat32Array()
	steps.resize(n)
	var total := 0.0
	for i in n:
		var u := float(i) / n
		# A slow swoop (up a fourth and back down, then a smaller dip) plus a 6-a-second wobble.
		var swoop := 0.22 * sin(TAU * u) + 0.08 * sin(TAU * 2.0 * u + 1.0)
		var wobble := 0.035 * sin(TAU * 15.0 * u)
		steps[i] = TAU * center * pow(2.0, swoop + wobble) / RATE
		total += steps[i]
	var fix := roundf(total / TAU) * TAU / total
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var noise := 0.0
	var noise2 := 0.0
	var rng := RandomNumberGenerator.new()   # its own dice: building a sound mustn't shift the game's random numbers
	rng.seed = 666
	for i in n:
		var u := float(i) / n
		phase += steps[i] * fix
		# Mostly a pure, singing tone; a touch of 2nd and 3rd harmonic makes it hollow and metallic.
		var saw := sin(phase) + 0.18 * sin(2.0 * phase) + 0.07 * sin(3.0 * phase)
		var swell := 0.75 + 0.25 * sin(TAU * 2.0 * u)   # breathes louder and softer as the bow moves
		var beat := pow(sin(fmod(u * 5.0, 1.0) * PI), 6.0)   # wing whooshes, 2 a second
		noise = lerpf(noise, rng.randf_range(-1.0, 1.0), 0.08)
		noise2 = lerpf(noise2, noise, 0.08)
		var s := saw * 0.42 * swell + noise2 * beat * 2.2
		data.encode_s16(i * 2, int(clampf(s * 0.6, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav


# ---------- Placeholder voices for taunts ----------
# syllables: [[pitch_start_Hz, pitch_end_Hz, seconds, loudness, gap_after_seconds], ...]
# Pitches are the voice's fundamental; harmonics on top make it sound vocal.
# rasp = gravelly growl (demons), breath = airy noise, vibrato = pitch wobble depth.
static func voice(syllables: Array, volume := 0.25, rasp := 0.0, breath := 0.05,
		vibrato := 0.02) -> AudioStreamWAV:
	var total := 0.0
	for s in syllables:
		total += s[2] + s[4]
	total += 0.05
	var n := int(RATE * total)
	var data := PackedByteArray()
	data.resize(n * 2)
	var harmonics := [1.0, 0.6, 0.45, 0.3, 0.2, 0.12]
	var phase := 0.0
	var noise := 0.0
	var i0 := 0
	for s in syllables:
		var len_n := int(RATE * s[2])
		for j in len_n:
			var u := float(j) / len_n
			var t := float(j) / RATE
			# soft start and end per syllable
			var env: float = minf(t / 0.015, 1.0) * minf((s[2] - t) / 0.04, 1.0) * s[3]
			var f: float = lerpf(s[0], s[1], u) * (1.0 + vibrato * sin(TAU * 5.5 * t))
			phase += TAU * f / RATE
			var v := 0.0
			for k in harmonics.size():
				v += sin(phase * (k + 1)) * harmonics[k]
			v /= 2.0
			if rasp > 0.0:   # flutter the loudness ~35 times a second: gravelly
				v *= 1.0 - rasp * (0.5 + 0.5 * sin(TAU * 35.0 * t + randf() * 0.6))
			noise = lerpf(noise, randf_range(-1.0, 1.0), 0.15)
			v += noise * breath * 3.0
			var idx := i0 + j
			if idx < n:
				data.encode_s16(idx * 2, int(clampf(v * env * volume, -1.0, 1.0) * 32767.0))
		i0 += len_n + int(RATE * s[4])
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav
