# Generated surface textures: wood grain, iron, stone, earth, leather, hay, plant skin.
# Made from noise at startup (no image files), greyscale so the piece's own colour
# tints them, and mapped "triplanar" so they never stretch on blocks of any size.
# Every surface is made once and shared.
extends RefCounted

# noise: FastNoiseLite type. freq: grain size (bigger = finer). stretch: how much the
# pattern is drawn out along the piece's height (wood and hay grain run lengthwise).
# dark: the darkest the pattern gets (1.0 = no pattern). bump: how strong the
# surface relief is. rough / metal: shininess.
const KINDS := {
	"wood": {"noise": FastNoiseLite.TYPE_SIMPLEX_SMOOTH, "freq": 0.035, "octaves": 4, "stretch": 7.0, "scale": 1.6,
		"dark": 0.62, "bump": 0.5, "rough": 0.82, "metal": 0.0},
	"metal": {"noise": FastNoiseLite.TYPE_SIMPLEX, "freq": 0.05, "octaves": 3, "stretch": 1.0, "scale": 2.0,
		"dark": 0.8, "bump": 0.25, "rough": 0.38, "metal": 0.75},
	"stone": {"noise": FastNoiseLite.TYPE_CELLULAR, "freq": 0.06, "octaves": 2, "stretch": 1.0, "scale": 0.45,
		"dark": 0.7, "bump": 0.7, "rough": 0.92, "metal": 0.0},
	"ground": {"noise": FastNoiseLite.TYPE_SIMPLEX_SMOOTH, "freq": 0.04, "octaves": 5, "stretch": 1.0, "scale": 0.4,
		"dark": 0.76, "bump": 0.35, "rough": 0.97, "metal": 0.0},
	"leather": {"noise": FastNoiseLite.TYPE_CELLULAR, "freq": 0.12, "octaves": 1, "stretch": 1.0, "scale": 3.0,
		"dark": 0.82, "bump": 0.35, "rough": 0.7, "metal": 0.0},
	"hay": {"noise": FastNoiseLite.TYPE_VALUE, "freq": 0.09, "octaves": 3, "stretch": 9.0, "scale": 1.4,
		"dark": 0.55, "bump": 0.8, "rough": 1.0, "metal": 0.0},
	"plant": {"noise": FastNoiseLite.TYPE_SIMPLEX_SMOOTH, "freq": 0.03, "octaves": 2, "stretch": 1.0, "scale": 2.5,
		"dark": 0.86, "bump": 0.15, "rough": 0.45, "metal": 0.0},
	"glossy": {"noise": FastNoiseLite.TYPE_SIMPLEX_SMOOTH, "freq": 0.03, "octaves": 2, "stretch": 1.0, "scale": 4.0,
		"dark": 0.9, "bump": 0.05, "rough": 0.22, "metal": 0.0},
	"cloth": {"noise": FastNoiseLite.TYPE_VALUE_CUBIC, "freq": 0.25, "octaves": 2, "stretch": 1.0, "scale": 2.0,
		"dark": 0.85, "bump": 0.3, "rough": 0.95, "metal": 0.0},
}
const SIZE := 256

static var _albedo := {}
static var _normal := {}


static func _noise(kind: String) -> FastNoiseLite:
	var k: Dictionary = KINDS[kind]
	var n := FastNoiseLite.new()
	n.noise_type = k["noise"]
	n.frequency = k["freq"]
	n.fractal_octaves = k["octaves"]
	n.seed = hash(kind) % 1000
	if k["noise"] == FastNoiseLite.TYPE_CELLULAR:
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	return n


static func _textures(kind: String) -> void:
	if _albedo.has(kind):
		return
	var k: Dictionary = KINDS[kind]
	var alb := NoiseTexture2D.new()
	alb.width = SIZE
	alb.height = SIZE
	alb.seamless = true
	alb.noise = _noise(kind)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(k["dark"], k["dark"], k["dark"]))
	ramp.set_color(1, Color.WHITE)
	alb.color_ramp = ramp
	_albedo[kind] = alb
	var nrm := NoiseTexture2D.new()
	nrm.width = SIZE
	nrm.height = SIZE
	nrm.seamless = true
	nrm.as_normal_map = true
	nrm.bump_strength = 6.0
	nrm.noise = _noise(kind)
	_normal[kind] = nrm


# Dress a material as this kind of surface ("" = leave it plain).
static func apply(m: StandardMaterial3D, kind: String) -> void:
	if kind == "" or not KINDS.has(kind):
		return
	var k: Dictionary = KINDS[kind]
	m.roughness = k["rough"]
	m.metallic = k["metal"]
	_textures(kind)
	m.albedo_texture = _albedo[kind]
	m.normal_enabled = true
	m.normal_texture = _normal[kind]
	m.normal_scale = k["bump"]
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	var s: float = k["scale"]
	m.uv1_scale = Vector3(s, s / k["stretch"], s)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
