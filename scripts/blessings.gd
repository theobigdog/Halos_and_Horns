# The kinds of blessed projectiles angels can throw. All deal holy damage;
# they differ in look and sound. Later these get tied to angel skins/cosmetics.
extends RefCounted

const KINDS := {
	"holy_light": {"label": "Holy Light", "color": Color(1.0, 0.9, 0.4)},
	"blessed_water": {"label": "Blessed Water", "color": Color(0.45, 0.75, 1.0)},
	"halo_ring": {"label": "Halo Ring", "color": Color(1.0, 0.8, 0.2)},
	"feather": {"label": "Feather", "color": Color(0.95, 0.95, 1.0)},
	"choir": {"label": "Choir Note", "color": Color(0.85, 0.65, 1.0)},
}


static func names() -> Array:
	return KINDS.keys()


static func label(kind: String) -> String:
	return KINDS[kind]["label"]


static func color(kind: String) -> Color:
	return KINDS[kind]["color"]
