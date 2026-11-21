# Hooded Rogue details (head only; the body is the Rogue's): gold stitched trim along the hood's edge,
# a glowing star clasp at the throat, a feather pinned to the hood and a gold tip on its peak.
# Coordinates are model space (see rogue.gd).
extends RefCounted

const R := preload("res://scripts/skin_details/rogue.gd")


static func head(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var s := R.space(sk, att, "head")
	# (the hood is part of this head's mesh, so "bare" changes nothing here)
	var g := R.gold()
	# gold trim: an arch of chunky segments following the hood's opening around the face
	var pts := []
	var n := 12
	for i in n + 1:
		var deg := lerpf(-105.0, 105.0, float(i) / n)
		var t := deg_to_rad(deg)
		# (the hood's rim sweeps back from the brim to the cheeks)
		var z := 0.58 - 0.24 * pow(absf(sin(t)), 2.5)
		if absf(deg) > 90.0:
			z = 0.34 - 0.07 * (absf(deg) - 90.0) / 15.0
		pts.append(Vector3(0.47 * sin(t), 1.3 + 0.5 * cos(t), z))
	for i in n:
		R.span(s, R.box(Vector3(0.06, 1.0, 0.04)), g, pts[i], pts[i + 1], Vector3(1, 1.08, 1), Vector3(0, 0, 1))
	# little glowing stitches on the trim
	var stitch := R.mat(Color(1.0, 0.95, 0.7), 0.4, 0.0, 1.6)
	for i in range(1, n, 2):
		R.put(s, R.ball(0.022, 6), stitch, pts[i] + Vector3(0, 0, 0.025))
	# star clasp at the throat
	R.put(s, R.star(0.085, 0.04), R.pulse(Color(1.0, 0.85, 0.4), 1.8), Vector3(0, 1.17, 0.45), Vector3(-10, 0, 0))
	R.put(s, R.ring(0.09, 0.115, 16), g, Vector3(0, 1.17, 0.44), Vector3(80, 0, 0))
	# a white feather pinned to the hood's right side
	R.feather_tuft(s, Vector3(-0.6, 1.72, -0.02), Vector3(-20, 0, 32), 1.0)
	# gold tip on the hood's peak
	R.put(s, R.cyl(0.0, 0.06, 0.12, 6), g, Vector3(0, 2.25, 0.05), Vector3(-10, 0, 0))
