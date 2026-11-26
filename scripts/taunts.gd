# Taunts: key 1 plays a random taunt (never the signature), key 2 plays your
# signature taunt. Angels are female (giggles, sing-song), demons are male
# (grunts, chuckles) - the reverse of Witch It, on purpose.
# Placeholder synthesized voices for now; real recorded clips replace them later,
# and eventually players pick their signature taunt in the wardrobe.
extends RefCounted

const Sfx = preload("res://scripts/sfx.gd")

const AngelTaunts = preload("res://scripts/angel_taunts.gd")
const DemonTaunts = preload("res://scripts/demon_taunts.gd")

# The taunts themselves are synthesized in angel_taunts.gd / demon_taunts.gd (Sara's list, Nov 25: holy trumpet,
# heavenly laugh, angel choir, come-here whistle; maniacal laugh, over-here whistle, deep nyah-nyah, low wolf
# whistle, "Ooover heeere!"). Key -> label shown on screen.
const TAUNTS := {"angel": AngelTaunts.TAUNTS, "demon": DemonTaunts.TAUNTS}
const SIGNATURES := {"angel": {"label": AngelTaunts.SIGNATURE_LABEL}, "demon": {"label": DemonTaunts.SIGNATURE_LABEL}}

static var _cache := {}


static func signature(role: String) -> String:
	return role + ":signature"


# Random pick from the side's pool. Never the signature (it isn't in the pool),
# and never the same one twice in a row.
static func pick_random(role: String, last: String) -> String:
	var names: Array = TAUNTS[role].keys()
	var options := []
	for taunt_name in names:
		var full: String = role + ":" + taunt_name
		if full != last:
			options.append(full)
	return options[randi() % options.size()]


static func label(full_name: String) -> String:
	var parts := full_name.split(":")
	if parts[1] == "signature":
		return SIGNATURES[parts[0]]["label"]
	return TAUNTS[parts[0]][parts[1]]


static var _lock := Mutex.new()
static var _warming := false


static func stream(full_name: String) -> AudioStreamWAV:
	_lock.lock()
	var have: AudioStreamWAV = _cache.get(full_name)
	_lock.unlock()
	if have:
		return have
	var parts := full_name.split(":")
	var made: AudioStreamWAV = AngelTaunts.make(parts[1]) if parts[0] == "angel" else DemonTaunts.make(parts[1])
	_lock.lock()
	if not _cache.has(full_name):
		_cache[full_name] = made
	made = _cache[full_name]
	_lock.unlock()
	return made


# Each taunt takes up to half a second to synthesize, and the first one used to be made right when it played,
# stalling the game (playtest, Nov 26). This makes them all in the background as the game starts.
static func warm_up() -> void:
	if _warming:
		return
	_warming = true
	var names := []
	for role in TAUNTS:
		for k in TAUNTS[role]:
			names.append(role + ":" + k)
		names.append(signature(role))
	WorkerThreadPool.add_task(func():
		for n in names:
			stream(n))
