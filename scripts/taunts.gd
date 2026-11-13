# Taunts: key 1 plays a random taunt (never the signature), key 2 plays your
# signature taunt. Angels are female (giggles, sing-song), demons are male
# (grunts, chuckles) - the reverse of Witch It, on purpose.
# Placeholder synthesized voices for now; real recorded clips replace them later,
# and eventually players pick their signature taunt in the wardrobe.
extends RefCounted

const Sfx = preload("res://scripts/sfx.gd")

# Syllables: [pitch start Hz, pitch end Hz, seconds, loudness, gap after]
const TAUNTS := {
	"angel": {
		"giggle": {"label": "Giggle", "syl": [[720, 690, 0.07, 0.9, 0.04], [700, 670, 0.07, 0.8, 0.04], [690, 650, 0.07, 0.75, 0.04], [670, 620, 0.08, 0.6, 0.0]]},
		"tee_hee": {"label": "Tee-hee", "syl": [[600, 760, 0.12, 0.8, 0.07], [650, 820, 0.18, 0.9, 0.0]]},
		"ooh_la_la": {"label": "Ooh la la", "syl": [[500, 700, 0.2, 0.8, 0.04], [560, 560, 0.12, 0.7, 0.03], [700, 540, 0.22, 0.85, 0.0]]},
		"hmph": {"label": "Hmph!", "syl": [[420, 330, 0.16, 0.9, 0.0]], "breath": 0.15},
		"sing_song": {"label": "La-la-laaa", "syl": [[523, 523, 0.14, 0.8, 0.02], [659, 659, 0.14, 0.8, 0.02], [784, 784, 0.3, 0.9, 0.0]], "vibrato": 0.035},
		"hmm": {"label": "Hmm?", "syl": [[440, 700, 0.3, 0.8, 0.0]]},
	},
	"demon": {
		"chuckle": {"label": "Heh heh heh", "syl": [[125, 112, 0.09, 0.9, 0.06], [122, 110, 0.09, 0.85, 0.06], [118, 105, 0.1, 0.8, 0.0]], "rasp": 0.5},
		"grunt": {"label": "Hrmph", "syl": [[110, 88, 0.25, 1.0, 0.0]], "rasp": 0.6, "breath": 0.12},
		"snort": {"label": "*snort*", "syl": [[95, 85, 0.18, 0.6, 0.0]], "rasp": 0.3, "breath": 0.4},
		"nyeh": {"label": "Nyeh!", "syl": [[165, 130, 0.3, 0.9, 0.0]], "rasp": 0.2},
		"growl": {"label": "Grrrr", "syl": [[80, 86, 0.6, 0.9, 0.0]], "rasp": 0.85},
		"huh": {"label": "Huh?", "syl": [[100, 150, 0.22, 0.9, 0.0]], "rasp": 0.3},
	},
}

const SIGNATURES := {
	"angel": {"label": "Ha-HA!", "syl": [[600, 640, 0.12, 0.8, 0.06], [820, 700, 0.26, 1.0, 0.0]]},
	"demon": {"label": "MWA-HA-HA!", "syl": [[140, 170, 0.2, 1.0, 0.05], [165, 160, 0.12, 0.9, 0.04], [155, 150, 0.12, 0.85, 0.04], [140, 100, 0.32, 0.9, 0.0]], "rasp": 0.45},
}

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


static func _data(full_name: String) -> Dictionary:
	var parts := full_name.split(":")
	if parts[1] == "signature":
		return SIGNATURES[parts[0]]
	return TAUNTS[parts[0]][parts[1]]


static func label(full_name: String) -> String:
	return _data(full_name)["label"]


static func stream(full_name: String) -> AudioStreamWAV:
	if not _cache.has(full_name):
		var d := _data(full_name)
		_cache[full_name] = Sfx.voice(d["syl"], 0.28, d.get("rasp", 0.0),
				d.get("breath", 0.05), d.get("vibrato", 0.02))
	return _cache[full_name]
