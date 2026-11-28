# Creative pieces made in code (Ted's wife's notes, Nov 21):
#  - "sidewalk": a raised concrete slab (curb height), with joints, to run along roads. Solid; resizable.
#    (Since Nov 28 it is drawn by ground_block.gd, like the "Sidewalk" ground block: a "sidewalk" piece in an
#    older map is the same thing.)
#  - "window": a flat picture to stick on a building's window: a furnished room seen through it (living
#    room, kitchen, bedroom, library) or a plain lit pane. It glows warmer at night, as if the lights
#    were on inside. No collision (it's paint on the glass).
extends RefCounted

const PropLib = preload("res://scripts/prop_library.gd")

const WINDOW_LOOKS := ["Living room", "Kitchen", "Bedroom", "Library", "Lit (plain)"]

const ROOM_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform int room = 0;
uniform float night = 0.0;
uniform vec3 wall = vec3(0.85, 0.72, 0.55);
float box(vec2 p, vec2 a, vec2 b) { return step(a.x, p.x) * step(p.x, b.x) * step(a.y, p.y) * step(p.y, b.y); }
void fragment() {
	vec2 p = vec2(UV.x, 1.0 - UV.y);   // 0,0 bottom left
	// the room: a back wall, a floor, and side walls in perspective for depth
	vec3 c = wall;
	float floor_y = 0.28;
	if (p.y < floor_y) c = vec3(0.45, 0.3, 0.2) * (0.8 + 0.2 * step(0.5, fract(p.x * 6.0)));
	float side = min(p.x, 1.0 - p.x);
	if (side < 0.12 && p.y > floor_y - (0.12 - side)) c = wall * 0.72;
	// a ceiling lamp's glow
	float glow = exp(-length((p - vec2(0.5, 0.92)) * vec2(1.6, 3.0)) * 3.0);
	if (room == 0) {          // living room: sofa, a picture, a floor lamp
		c = mix(c, vec3(0.55, 0.15, 0.18), box(p, vec2(0.2, 0.22), vec2(0.78, 0.4)));
		c = mix(c, vec3(0.45, 0.1, 0.13), box(p, vec2(0.2, 0.38), vec2(0.78, 0.48)));
		c = mix(c, vec3(0.3, 0.45, 0.6), box(p, vec2(0.38, 0.6), vec2(0.62, 0.78)));
		c = mix(c, vec3(0.75, 0.6, 0.25), box(p, vec2(0.36, 0.58), vec2(0.64, 0.8)) - box(p, vec2(0.38, 0.6), vec2(0.62, 0.78)));
		c = mix(c, vec3(0.2), box(p, vec2(0.85, 0.22), vec2(0.86, 0.62)));
		c = mix(c, vec3(1.0, 0.85, 0.5), box(p, vec2(0.81, 0.62), vec2(0.9, 0.7)));
		glow += exp(-length(p - vec2(0.855, 0.66)) * 9.0);
	} else if (room == 1) {   // kitchen: cupboards, a counter, a window with a pot plant
		c = mix(c, vec3(0.92, 0.92, 0.88), box(p, vec2(0.08, 0.2), vec2(0.92, 0.42)));
		c = mix(c, vec3(0.3, 0.3, 0.32), box(p, vec2(0.08, 0.42), vec2(0.92, 0.45)));
		c = mix(c, vec3(0.6, 0.75, 0.6), box(p, vec2(0.08, 0.62), vec2(0.4, 0.82)));
		c = mix(c, vec3(0.6, 0.75, 0.6), box(p, vec2(0.6, 0.62), vec2(0.92, 0.82)));
		c = mix(c, vec3(0.2, 0.5, 0.25), box(p, vec2(0.46, 0.45), vec2(0.54, 0.55)));
		for (float i = 0.0; i < 4.0; i++) c = mix(c, vec3(0.75, 0.6, 0.2), box(p, vec2(0.15 + i * 0.2, 0.3), vec2(0.17 + i * 0.2, 0.34)));
	} else if (room == 2) {   // bedroom: a bed with a quilt and pillows, a bedside lamp
		c = mix(c, vec3(0.45, 0.28, 0.18), box(p, vec2(0.15, 0.2), vec2(0.75, 0.5)));
		c = mix(c, vec3(0.35, 0.45, 0.75), box(p, vec2(0.15, 0.2), vec2(0.75, 0.33)));
		c = mix(c, vec3(0.95), box(p, vec2(0.18, 0.34), vec2(0.4, 0.42)));
		c = mix(c, vec3(0.95), box(p, vec2(0.48, 0.34), vec2(0.7, 0.42)));
		c = mix(c, vec3(0.4, 0.3, 0.2), box(p, vec2(0.8, 0.2), vec2(0.92, 0.35)));
		c = mix(c, vec3(1.0, 0.8, 0.5), box(p, vec2(0.82, 0.38), vec2(0.9, 0.46)));
		glow += exp(-length(p - vec2(0.86, 0.43)) * 8.0);
	} else if (room == 3) {   // library: tall shelves of coloured books
		if (box(p, vec2(0.1, 0.2), vec2(0.9, 0.9)) > 0.5) {
			c = vec3(0.35, 0.22, 0.12);
			float shelf = fract((p.y - 0.2) / 0.175);
			float book = floor(p.x * 34.0);
			vec3 bc = vec3(fract(sin(book * 12.9) * 437.5), fract(sin(book * 78.2) * 437.5), fract(sin(book * 31.4) * 437.5));
			if (shelf > 0.12 && fract(sin(book * 3.7 + floor((p.y - 0.2) / 0.175)) * 99.0) > 0.15) c = mix(vec3(0.25), bc, 0.7) * (shelf < 0.9 ? 1.0 : 0.0);
		}
	} else {                  // just a warm lit pane
		c = vec3(1.0, 0.85, 0.55);
	}
	// curtains each side, and the window's cross bars over it all
	float curtain = max(smoothstep(0.1, 0.0, p.x), smoothstep(0.9, 1.0, p.x));
	c = mix(c, vec3(0.6, 0.15, 0.2) * (0.8 + 0.2 * sin(p.x * 80.0)), curtain * (room == 4 ? 0.0 : 1.0));
	float bars = max(step(abs(p.x - 0.5), 0.015), step(abs(p.y - 0.55), 0.015));
	c = mix(c, vec3(0.92, 0.92, 0.88), bars);
	c *= 0.75 + 0.25 * glow;
	ALBEDO = c * 0.6;
	ROUGHNESS = 0.15;
	SPECULAR = 0.8;
	EMISSION = c * (0.12 + night * 0.9) * (room == 4 ? 1.6 : 1.0) * (1.0 - bars * 0.8);
}
"""

static var _room_mats := {}
static var _shader: Shader
static var _night := 0.0


# graphics.gd: how dark it is (0 day .. 1 night): windows glow more.
static func set_night(n: float) -> void:
	_night = n
	for m in _room_mats.values():
		(m as ShaderMaterial).set_shader_parameter("night", clampf(n * 1.4, 0.0, 1.0))


static func _room_mat(look: int) -> ShaderMaterial:
	if not _room_mats.has(look):
		if _shader == null:
			_shader = Shader.new()
			_shader.code = ROOM_SHADER
		var m := ShaderMaterial.new()
		m.shader = _shader
		m.set_shader_parameter("room", look)
		m.set_shader_parameter("night", clampf(_night * 1.4, 0.0, 1.0))
		m.set_shader_parameter("wall", [Vector3(0.85, 0.72, 0.55), Vector3(0.9, 0.88, 0.75), Vector3(0.7, 0.75, 0.85),
				Vector3(0.6, 0.5, 0.4), Vector3(1, 1, 1)][clampi(look, 0, 4)])
		_room_mats[look] = m
	return _room_mats[look]


# A window picture: a flat panel facing +Z (stand it against a window, facing out).
static func make_window(p: Dictionary) -> Node3D:
	var sz: Vector3 = _vec(p.get("size", [1.0, 1.4, 0.02]))
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(sz.x, sz.y)
	mi.mesh = q
	mi.material_override = _room_mat(int(p.get("look", 0)))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _vec(a) -> Vector3:
	if a is Array and a.size() == 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ONE
