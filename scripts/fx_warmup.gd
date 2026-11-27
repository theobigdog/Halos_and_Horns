# Ted, Nov 26 playtest: the game froze for up to a second the first time someone stomped, flung Hellfire or
# threw a Vacuum Orb (as a guest, and the orb for the host too). The first use of each effect made its sounds
# right then (synthesized in code: the orb's four take about half a second together, Hellfire's about 0.2 s)
# and compiled its shaders on the spot. Now:
#   sounds():          makes all those sounds in the background while the game starts up
#   shaders(camera):   draws every effect shader once, tiny, just in front of the camera for a few frames
#                      when a player's camera appears, so the graphics card has them all ready
extends RefCounted

const Effects = preload("res://scripts/effects.gd")
const Fire = preload("res://scripts/fire.gd")
const Vortex = preload("res://scripts/vortex.gd")
const Projectile = preload("res://scripts/projectile.gd")
const FireSounds = preload("res://scripts/fire_sounds.gd")
const StompSounds = preload("res://scripts/stomp_sounds.gd")
const VacuumSounds = preload("res://scripts/vacuum_sounds.gd")
const BlessingSounds = preload("res://scripts/blessing_sounds.gd")
const Blessings = preload("res://scripts/blessings.gd")

const VORTEX_SHADERS := ["core", "debris", "ground", "halo", "shell", "streak"]

static var _sounds_started := false


static func sounds() -> void:
	if _sounds_started:
		return
	_sounds_started = true
	var kinds: Array = Blessings.names() + ["book", "vacuum"]
	WorkerThreadPool.add_task(func():
		# (only the pure _make functions run here; the caches are filled back on the main thread)
		var made := []
		made.append([FireSounds._cache, "whoosh", FireSounds._make_whoosh()])
		made.append([FireSounds._cache, "ignite", FireSounds._make_ignite()])
		made.append([FireSounds._cache, "burn", FireSounds._make_burn()])
		for level in StompSounds.LEVELS:
			made.append([StompSounds._cache, level, StompSounds._make(float(level) / (StompSounds.LEVELS - 1), level)])
		made.append([VacuumSounds._cache, "open", VacuumSounds._make_open()])
		made.append([VacuumSounds._cache, "suck", VacuumSounds._make_suck()])
		made.append([VacuumSounds._cache, "caught", VacuumSounds._make_caught()])
		made.append([VacuumSounds._cache, "close", VacuumSounds._make_close()])
		for k in kinds:
			made.append([BlessingSounds._cache, "impact_" + k, BlessingSounds._make_impact(k)])
		_store.call_deferred(made))


static func _store(made: Array) -> void:
	for m in made:
		var cache: Dictionary = m[0]
		if not cache.has(m[1]):
			cache[m[1]] = m[2]


static func _materials() -> Array:
	var mats := []
	for key in Effects.SHADERS:
		mats.append(Effects._mat(key))
	mats.append(Fire._shader("core", Fire.CORE_SHADER))
	mats.append(Fire._shader("dome", Fire.DOME_SHADER))
	mats.append(Fire._shader("ember", Fire.EMBER_SHADER))
	mats.append(Fire._shader("tongue", Fire.TONGUE_SHADER))
	for name in VORTEX_SHADERS:
		if not Vortex._shaders.has(name):
			var sh := Shader.new()
			sh.code = Vortex._code(name)
			Vortex._shaders[name] = sh
		var m := ShaderMaterial.new()
		m.shader = Vortex._shaders[name]
		mats.append(m)
	var sprite := ShaderMaterial.new()
	sprite.shader = Projectile._shader("sprite", Projectile.SPRITE_SHADER)
	mats.append(sprite)
	var ribbon := ShaderMaterial.new()
	ribbon.shader = Projectile._shader("ribbon", Projectile.RIBBON_SHADER)
	mats.append(ribbon)
	return mats


static func shaders(camera: Camera3D) -> void:
	if camera == null or DisplayServer.get_name() == "headless":
		return
	# (the textures made in code too: small, but no reason to make them mid-fight)
	Fire._scorch_textures()
	Effects._scorch_tex()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.002
	var dots := []
	for m in _materials():
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 4.0   # (some move their vertices in the shader: keep them drawn anyway)
		camera.add_child(mi)
		mi.position = Vector3(0, 0, -0.3)
		dots.append(mi)
	var tree := camera.get_tree()
	for i in 4:
		await tree.process_frame
	for d in dots:
		if is_instance_valid(d):
			d.queue_free()
