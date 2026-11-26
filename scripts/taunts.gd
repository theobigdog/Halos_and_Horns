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


static func stream(full_name: String) -> AudioStreamWAV:
	if not _cache.has(full_name):
		var parts := full_name.split(":")
		_cache[full_name] = AngelTaunts.make(parts[1]) if parts[0] == "angel" else DemonTaunts.make(parts[1])
	return _cache[full_name]
