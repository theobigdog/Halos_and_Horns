# Drives "building together" for tests/test_building.sh: one of three scripted builders.
#   --buildbot=host   (Abe) starts building once everyone's in, places a block, tries to grab
#                     Ava's piece (must be refused), makes Cid view-only, then ends building.
#   --buildbot=ava    places a crate and a wall, moves the host's block, deletes and un-deletes
#                     the wall, and keeps her crate selected (claimed).
#   --buildbot=cheat  (Cid) a modified game: sends junk edits straight to the host, floods it,
#                     touches Ava's claimed crate, and keeps building after being made view-only.
# Everyone prints the shared map's fingerprint at the end; they must all match.
extends Node

var main
var role := ""
var _t := -1.0                 # seconds since building started here
var _done := {}
var _quit_at := -1.0


func log_line(text: String) -> void:
	print("[build] " + text)


func _process(delta: float) -> void:
	if _quit_at > 0.0:
		_quit_at -= delta
		if _quit_at <= 0.0:
			get_tree().quit()
		return
	var ed = main.editor
	if _t < 0.0:
		if role == "host" and main.net and main.net.is_host and main.net.peers.size() >= 3 and not _done.has("start"):
			_done["start"] = true
			main.net.start_building()
		if ed != null and ed.online:
			_t = 0.0
			log_line("%s is building (%d pieces)" % [role, ed.map["pieces"].size()])
		return
	if role != "host" and not main.building_online:
		log_line("%s: building ended" % role)
		_quit_at = 1.0
		return
	_t += delta
	match role:
		"host": _host(ed)
		"ava": _ava(ed)
		"cheat": _cheat(ed)


func at(t: float, key: String) -> bool:
	if _t >= t and not _done.has(key):
		_done[key] = true
		return true
	return false


func find(ed, pred: Callable) -> int:
	for i in ed.map["pieces"].size():
		if pred.call(ed.map["pieces"][i]):
			return i
	return -1


func _host(ed) -> void:
	if at(2.0, "block"):
		var i: int = ed.place("block", Vector3(6, 0, 6))
		ed.set_value(i, "color", "#ff00ff")
		log_line("host placed block %s" % ed.piece_id(i))
	if at(4.5, "grab"):
		var crate := find(ed, func(p): return p.get("prop", "") == "crate" and p["pos"][0] < -3.0)
		ed.select(crate)
		log_line("host tried to grab Ava's crate: selected=%d (claimed by %s)" % [ed.selected, ed.claims.values()])
	if at(6.0, "viewonly"):
		for id in main.net.peers:
			if main.net.peers[id]["name"] == "Cid":
				main.net.build_set_can(id, false)
	if at(11.0, "print"):
		log_line("final %s" % _fingerprint(ed))
		log_line("host refused %d edits" % main.net.build_refused)
		log_line("pieces: %s" % ", ".join(ed.map["pieces"].map(func(p): return p["type"] + ("/" + p.get("prop", p.get("model", "")) if p.has("prop") or p.has("model") else ""))))
		var b := find(ed, func(p): return p.get("color", "") == "#ff00ff")
		log_line("magenta block at %s" % [ed.map["pieces"][b]["pos"] if b >= 0 else "nowhere"])
		var c := find(ed, func(p): return p.get("prop", "") == "crate" and p["pos"][0] < -3.0)
		log_line("Ava's crate at %s" % [ed.map["pieces"][c]["pos"] if c >= 0 else "nowhere"])
	if at(12.0, "end"):
		main.net.build_end()
	if at(13.0, "lobby"):
		log_line("lobby map has %d pieces, building=%s" % [main.map_data["pieces"].size(), main.building_online])
		_quit_at = 2.0


func _ava(ed) -> void:
	if at(1.0, "place"):
		ed.place("prop:crate", Vector3(-4, 0, 3))
		ed.place("model:dungeon/wall", Vector3(0, 0, -6))
		ed.select(-1)
	if at(3.0, "claim"):
		ed.select(find(ed, func(p): return p.get("prop", "") == "crate" and p["pos"][0] < -3.0))
		log_line("ava holds the crate: %s" % ed.piece_id(ed.selected))
	if at(5.2, "move"):
		var b := find(ed, func(p): return p.get("color", "") == "#ff00ff")
		ed.select(b)
		if ed.selected == b and b >= 0:
			ed.set_value(b, "pos", Vector3(8, 1, 8))
			log_line("ava moved the host's block")
		else:
			log_line("ava couldn't get the host's block")
	if at(5.6, "reclaim"):
		ed.select(find(ed, func(p): return p.get("prop", "") == "crate" and p["pos"][0] < -3.0))
	if at(7.5, "delwall"):
		ed.select(find(ed, func(p): return p.get("model", "") == "dungeon/wall"))
		ed.delete_selected()
		log_line("ava deleted the wall: %d walls" % ed.map["pieces"].filter(func(p): return p.get("model", "") == "dungeon/wall").size())
	if at(8.0, "undo"):
		ed.undo()
		log_line("ava undid it: %d walls" % ed.map["pieces"].filter(func(p): return p.get("model", "") == "dungeon/wall").size())
		ed.select(find(ed, func(p): return p.get("prop", "") == "crate" and p["pos"][0] < -3.0))
	if at(10.5, "print"):
		log_line("final %s" % _fingerprint(ed))


# A cheater's game: edits go straight to the host, and its own screen shows them (until put right).
func _send_raw(ed, ops: Array) -> void:
	ed.apply_remote(ops)
	main.net.c_build_ops.rpc_id(1, JSON.stringify(ops))


func _cheat(ed) -> void:
	if at(2.0, "junk"):
		var spawn := find(ed, func(p): return p["type"] == "angel_spawn")
		_send_raw(ed, [
			{"o": "put", "id": "x1", "p": {"type": "nuke", "pos": [0, 0, 0], "id": "x1"}},
			{"o": "put", "id": "x2", "p": {"type": "shrine", "pos": [10, 0, -10], "id": "x2"}},
			{"o": "put", "id": "x3", "p": {"type": "shrine", "pos": [12, 0, -10], "id": "x3"}},
			{"o": "del", "id": ed.piece_id(spawn)},
			{"o": "set", "k": "evil", "v": 1},
			{"o": "set", "k": "size", "v": 99999},
			{"o": "put", "id": "bad id!", "p": {"type": "block", "pos": [0, 0, 0], "id": "bad id!"}},
		])
		log_line("cheat sent junk")
	if at(3.0, "flood"):
		for k in 60:
			_send_raw(ed, [{"o": "put", "id": "f%d" % k, "p": {"type": "nuke", "pos": [0, 0, 0], "id": "f%d" % k}}])
		log_line("cheat flooded")
	if at(6.8, "steal"):
		var c := find(ed, func(p): return p.get("prop", "") == "crate" and p["pos"][0] < -3.0)
		var p: Dictionary = ed.map["pieces"][c].duplicate(true)
		p["pos"] = [20, 0, 20]
		_send_raw(ed, [{"o": "put", "id": p["id"], "p": p}])
		log_line("cheat moved Ava's crate (locally)")
	if at(8.5, "viewonly"):
		log_line("cheat can_edit=%s" % ed.can_edit)
		_send_raw(ed, [{"o": "put", "id": "v1", "p": {"type": "block", "pos": [3, 1, 3], "size": [1, 1, 1], "color": "#123456", "id": "v1"}}])
	if at(10.5, "print"):
		log_line("final %s" % _fingerprint(ed))


# The shared map, order aside (pieces sorted by id).
func _fingerprint(ed) -> String:
	var ps: Array = ed.map["pieces"].duplicate(true)
	ps.sort_custom(func(a, b): return a.get("id", "") < b.get("id", ""))
	var m: Dictionary = ed.map.duplicate(true)
	m["pieces"] = ps
	return "%s (%d pieces, size %s)" % [JSON.stringify(m).md5_text().substr(0, 12), ps.size(), m["size"]]
