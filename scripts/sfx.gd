# Placeholder sound effects, generated in code so there are no audio files yet.
# Soft, chime-like tones: sine partials with a gentle attack and a smooth decay.
# Swap these for real recorded sounds later.
extends RefCounted

const RATE := 22050


# Bell/chime: a few sine partials (Hz, relative loudness) with exponential decay.
# shimmer adds a slow wobble; air adds soft filtered noise (breathy, feathery).
static func chime(partials: Array, seconds: float, volume := 0.2, decay := 5.0,
		shimmer := 0.0, air := 0.0, glide := 1.0) -> AudioStreamWAV:
	var n := int(RATE * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phases := []
	for p in partials:
		phases.append(0.0)
	var noise := 0.0
	for i in n:
		var t := float(i) / RATE
		var attack := minf(t / 0.015, 1.0)          # 15 ms fade-in: no click
		var env := attack * exp(-decay * t / seconds)
		var tail := minf((seconds - t) / 0.03, 1.0)  # fade the last 30 ms to silence
		var bend := lerpf(1.0, glide, float(i) / n)  # pitch glide over the sound
		var wobble := 1.0 + shimmer * sin(TAU * 6.0 * t)
		var s := 0.0
		for k in partials.size():
			var freq: float = partials[k][0] * bend * wobble
			phases[k] += TAU * freq / RATE
			s += sin(phases[k]) * partials[k][1]
		if air > 0.0:
			noise = lerpf(noise, randf_range(-1.0, 1.0), 0.08)   # low-passed noise
			s += noise * air * 4.0
		data.encode_s16(i * 2, int(clampf(s * env * tail * volume, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav


# Each blessing type gets its own throw sound.
static func throw_sound(kind: String) -> AudioStreamWAV:
	match kind:
		"holy_light":     # soft high shimmer
			return chime([[1320.0, 0.6], [1980.0, 0.3], [2640.0, 0.15]], 0.35, 0.16, 4.0, 0.004)
		"blessed_water":  # bubbly, wobbling droplet
			return chime([[700.0, 0.7], [1050.0, 0.3]], 0.3, 0.16, 5.0, 0.04, 0.0, 1.5)
		"halo_ring":      # two clean ringing tones
			return chime([[988.0, 0.5], [1480.0, 0.5]], 0.45, 0.14, 3.5)
		"feather":        # breathy, airy puff
			return chime([[600.0, 0.15]], 0.3, 0.14, 4.0, 0.0, 0.5, 0.7)
		"choir":          # tiny "aah" chord
			return chime([[523.0, 0.5], [659.0, 0.4], [784.0, 0.4], [1046.0, 0.2]], 0.5, 0.12, 3.0, 0.006)
	return chime([[1320.0, 1.0]], 0.3)


static func hit_sound() -> AudioStreamWAV:
	# soft bright "ting"
	return chime([[1760.0, 0.6], [2640.0, 0.3], [3520.0, 0.1]], 0.4, 0.2, 6.0)


static func caught_sound() -> AudioStreamWAV:
	# gentle rising chord swell
	return chime([[523.0, 0.4], [659.0, 0.35], [784.0, 0.35], [1046.0, 0.25]], 1.0, 0.18, 2.5, 0.005, 0.0, 1.12)


static func possess_sound() -> AudioStreamWAV:
	# low, smooth demonic "whumm"
	return chime([[110.0, 0.7], [165.0, 0.3]], 0.45, 0.3, 4.0, 0.0, 0.3, 0.7)
