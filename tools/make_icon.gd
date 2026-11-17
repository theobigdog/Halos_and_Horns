extends SceneTree
# Turns icon.svg into icon.ico (the Windows .exe and taskbar icon) and a
# preview icon.png. Run it after changing icon.svg:
#   godot --headless -s res://tools/make_icon.gd
# The .ico holds the picture at 16, 24, 32, 48, 64, 128 and 256 pixels, each
# stored as a PNG (Windows Vista and later read those).

const SIZES := [16, 24, 32, 48, 64, 128, 256]


func _initialize() -> void:
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	if svg == "":
		print("make_icon: no icon.svg")
		quit(1)
		return
	var pngs := []
	for s in SIZES:
		var img := Image.new()
		if img.load_svg_from_string(svg, s / 256.0) != OK:
			print("make_icon: couldn't draw the svg at %d px" % s)
			quit(1)
			return
		pngs.append(img.save_png_to_buffer())
		if s == 256:
			img.save_png("res://icon.png")
	# ICO: a 6-byte header, a 16-byte entry per picture, then the pictures.
	var out := PackedByteArray()
	out.resize(6 + 16 * SIZES.size())
	out.encode_u16(0, 0)
	out.encode_u16(2, 1)               # 1 = icon
	out.encode_u16(4, SIZES.size())
	var offset := out.size()
	for i in SIZES.size():
		var e := 6 + 16 * i
		var s: int = SIZES[i]
		out[e] = s % 256                   # width (0 means 256)
		out[e + 1] = s % 256               # height
		out[e + 2] = 0                     # no palette
		out[e + 3] = 0
		out.encode_u16(e + 4, 1)           # colour planes
		out.encode_u16(e + 6, 32)          # bits per pixel
		out.encode_u32(e + 8, pngs[i].size())
		out.encode_u32(e + 12, offset)
		offset += pngs[i].size()
	for p in pngs:
		out.append_array(p)
	var f := FileAccess.open("res://icon.ico", FileAccess.WRITE)
	f.store_buffer(out)
	f.close()
	print("make_icon: wrote icon.ico (%d bytes) and icon.png" % out.size())
	quit()
