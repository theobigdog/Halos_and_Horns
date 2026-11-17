# Renders every song and checks it: the right length, loud enough, no clipping or
# broken numbers, and a looping song's end flows into its start.
#   godot --headless -s res://tests/test_music.gd
#   (add  -- --save=C:/some/folder  to also write each song as a .wav to listen to)
extends SceneTree

const Music = preload("res://scripts/music.gd")

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _initialize() -> void:
	var save_dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--save="):
			save_dir = a.trim_prefix("--save=")
	for song_name in Music.SONGS:
		var song: Dictionary = Music.SONGS[song_name]
		var t0 := Time.get_ticks_msec()
		var wav := Music.render(song)
		var ms := Time.get_ticks_msec() - t0
		var data := wav.data   # (copy it once: each wav.data read makes a fresh copy)
		var frames := data.size() / 4
		var seconds := float(frames) / Music.RATE
		var expected: float = song["bars"] * int(song.get("beats", 4)) * 60.0 / song["bpm"]
		var looping: bool = song.get("loop", true)
		print("%s: %.1f s of music, rendered in %.1f s" % [song_name, seconds, ms / 1000.0])
		if looping:
			check(absf(seconds - expected) < 0.01, "%s is exactly %d bars long" % [song_name, song["bars"]])
		else:
			check(seconds > expected, "%s has room for its last note to ring out" % song_name)
		var peak := 0
		var sum := 0.0
		for i in range(0, frames * 2, 7):
			var v := absi(data.decode_s16(i * 2))
			peak = maxi(peak, v)
			sum += v
		var avg := sum / (frames * 2 / 7)
		check(peak > 20000 and peak < 32767, "%s peaks at a healthy level, without clipping (%d)" % [song_name, peak])
		check(avg > 1200, "%s isn't mostly silence (average %d)" % [song_name, int(avg)])
		if looping:
			# The last sample and the first should be close: no click at the loop point.
			var last := data.decode_s16((frames - 1) * 4)
			var first := data.decode_s16(0)
			check(absi(last - first) < 6000, "%s loops without a click (%d -> %d)" % [song_name, last, first])
			check(wav.loop_mode == AudioStreamWAV.LOOP_FORWARD and wav.loop_end == frames, "%s is set to loop" % song_name)
		check(ms < 30000, "%s renders in under 30 s (it runs in the background)" % song_name)
		if save_dir != "":
			wav.save_to_wav(save_dir.path_join(song_name + ".wav"))
	print("\nMUSIC TESTS: %s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
