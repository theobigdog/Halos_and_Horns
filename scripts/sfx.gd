# Placeholder sound effects, generated in code so there are no audio files yet.
# Swap these for real sounds later.
extends RefCounted

const RATE := 22050


# A tone sliding from f_start to f_end Hz, with a quick fade-out.
# noise_mix 0-1 blends in white noise (for whooshy sounds).
static func tone(f_start: float, f_end: float, seconds: float, volume := 0.5, noise_mix := 0.0) -> AudioStreamWAV:
	var n := int(RATE * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var freq := lerpf(f_start, f_end, t)
		phase += TAU * freq / RATE
		var env := minf(t * 30.0, 1.0) * (1.0 - t)   # tiny attack, linear fade
		var s := lerpf(sin(phase), randf_range(-1.0, 1.0), noise_mix)
		data.encode_s16(i * 2, int(clampf(s * env * volume, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav


static func throw_sound() -> AudioStreamWAV:
	return tone(900.0, 300.0, 0.12, 0.25, 0.6)


static func hit_sound() -> AudioStreamWAV:
	return tone(1300.0, 1900.0, 0.09, 0.45)


static func caught_sound() -> AudioStreamWAV:
	return tone(500.0, 1100.0, 0.35, 0.5)


static func possess_sound() -> AudioStreamWAV:
	return tone(220.0, 90.0, 0.25, 0.5, 0.3)
