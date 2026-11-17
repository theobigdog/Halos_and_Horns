# Updater. At startup it asks GitHub whether a newer release exists. When the
# player clicks the menu button, it downloads the new game file, checks its
# signature, swaps it in for the running game file and restarts.
#
# Signed updates only. The release workflow signs each build with a private key
# kept in a GitHub secret (UPDATE_SIGNING_KEY), and this game carries the
# matching public key (update_key.gd). The signature covers a short statement
# naming the version, the file and its SHA-256:
#
#   Halos & Horns update
#   version 0.5.6
#   file HalosAndHorns.x86_64
#   sha256 <64 hex digits>
#
# The game writes that statement itself, from the release's tag and from the
# file it actually downloaded, and installs nothing unless the signature
# matches. So a swapped or damaged file, a file from some other release, or an
# older build passed off as a newer one is never run. Anything unsigned (no
# key in this build, no signature on the release) falls back to opening the
# download page.
#
# How the swap works: a running program can't be overwritten, but it can be
# renamed. So the game renames itself to "<name>.old", moves the download into
# its place, starts it and quits. The new copy deletes the ".old" file.
#
# Only exported Windows and Linux builds check. Run from the Godot editor (or
# from source) this does nothing.
extends Node

signal changed   # state, button_text or note changed: the menu redraws its update row

const UpdateKey = preload("res://scripts/update_key.gd")
const REPO := "theobigdog/Halos_and_Horns"
const API_URL := "https://api.github.com/repos/" + REPO + "/releases/latest"
const DOWNLOAD_PREFIX := "https://github.com/" + REPO + "/releases/download/"
const PAGE_URL := "https://github.com/" + REPO + "/releases/latest"
# The file each platform downloads (the names release-builds.yml attaches),
# and next to it on the release, the same name plus ".sig".
const ASSETS := {"Windows": "HalosAndHorns.exe", "Linux": "HalosAndHorns.x86_64"}
const AGENT := "User-Agent: HalosAndHorns-updater"
const MAX_SIGNATURE := 4096   # bytes; an RSA signature is a few hundred

var state := "idle"     # idle, available, downloading, failed, restarting
var button_text := ""   # what the menu's update button says
var note := ""          # a line under it
var latest := ""        # the newer version's number, e.g. "0.4.1"
var signed := false     # the newer version can be installed here (else: download page)

var _key: CryptoKey     # null when this build carries no key
var _exe := ""          # the running game file
var _url := ""
var _sig_url := ""
var _size := 0
var _signature := PackedByteArray()
var _download: HTTPRequest
var _percent := -1
var _testing := false   # a test pointed us at a stand-in for GitHub
var _auto := false      # a test asked us to press the button


# "v0.4.1" or "0.4.1 (Hellfire)" -> [0, 4, 1]
static func version_numbers(version: String) -> Array:
	var found := RegEx.create_from_string("\\d+(\\.\\d+)*").search(version)
	var numbers := []
	if found:
		for part in found.get_string().split("."):
			numbers.append(int(part))
	return numbers


static func is_newer(candidate: String, current: String) -> bool:
	var a := version_numbers(candidate)
	var b := version_numbers(current)
	for i in max(a.size(), b.size()):
		var x: int = a[i] if i < a.size() else 0
		var y: int = b[i] if i < b.size() else 0
		if x != y:
			return x > y
	return false


# What a release signs (see the top of the file). The release workflow writes
# exactly this with printf: change one, change the other.
static func statement(version: String, file_name: String, sha256: String) -> String:
	return "Halos & Horns update\nversion %s\nfile %s\nsha256 %s\n" % [version, file_name, sha256]


# Does `signature` sign the statement for this version and this file on disk?
static func signature_ok(key: CryptoKey, version: String, file_name: String, path: String,
		signature: PackedByteArray) -> bool:
	if key == null or signature.is_empty():
		return false
	var text := statement(version, file_name, FileAccess.get_sha256(path))
	return Crypto.new().verify(HashingContext.HASH_SHA256, text.sha256_buffer(), signature, key)


static func load_key(pem: String) -> CryptoKey:
	if pem.strip_edges() == "":
		return null
	var key := CryptoKey.new()
	return key if key.load_from_string(pem, true) == OK else null


func _show(new_state: String, new_button: String, new_note := "") -> void:
	state = new_state
	button_text = new_button
	note = new_note
	changed.emit()


# Called once at startup with the running game's version.
func check(current_version: String) -> void:
	if not OS.has_feature("template") or not ASSETS.has(OS.get_name()):
		return
	if version_numbers(current_version).is_empty():
		return   # a "dev" build made by hand: there's no telling what's newer than it
	_exe = OS.get_executable_path()
	_key = load_key(UpdateKey.PEM)
	_remove_leftovers()
	var api := API_URL
	# Automated testing (debug builds only):
	#   game -- --update-api=http://127.0.0.1:8000/latest.json --update-click
	if OS.is_debug_build():
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--update-api="):
				api = a.trim_prefix("--update-api=")
				_testing = true
			elif a == "--update-click":
				_auto = true
	var req := HTTPRequest.new()
	req.timeout = 15
	add_child(req)
	req.request_completed.connect(func(result, code, _headers, body):
		req.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			_read_release(body.get_string_from_utf8(), current_version))
	req.request(api, ["Accept: application/vnd.github+json", AGENT])


# The last update's ".old" file. Right after an update the old game may still be
# closing (Windows won't delete it until then), so try again a little later.
func _remove_leftovers() -> void:
	var old := _exe + ".old"
	if FileAccess.file_exists(old) and DirAccess.remove_absolute(old) != OK:
		get_tree().create_timer(5.0).timeout.connect(func(): DirAccess.remove_absolute(old))


func _read_release(json: String, current_version: String) -> void:
	var release = JSON.parse_string(json)
	if not release is Dictionary or not is_newer(str(release.get("tag_name", "")), current_version):
		return
	latest = ".".join(version_numbers(str(release["tag_name"])).map(func(n): return str(n)))
	var file_name: String = ASSETS[OS.get_name()]
	for asset in release.get("assets", []):
		if not asset is Dictionary:
			continue
		if asset.get("name", "") == file_name:
			_url = str(asset.get("browser_download_url", ""))
			_size = int(asset.get("size", 0))
		elif asset.get("name", "") == file_name + ".sig":
			_sig_url = str(asset.get("browser_download_url", ""))
	# Only from this game's own releases (a test's stand-in aside). A release
	# exists a few minutes before its builds are attached; until our file and
	# its signature are both there, all we can offer is the download page.
	var from_github := _url.begins_with(DOWNLOAD_PREFIX) and _sig_url.begins_with(DOWNLOAD_PREFIX)
	signed = _key != null and _url != "" and _sig_url != "" and (from_github or _testing)
	if signed:
		_show("available", "Update to version %s" % latest)
	else:
		_show("available", "Version %s is out: open the download page" % latest)
	print("[updater] version %s is available (%s)" % [latest, "signed" if signed else "download page only"])
	if _auto:
		install()


# The menu's update button.
func install() -> void:
	if state == "failed" or (state == "available" and not signed):
		_open_page()
		return
	if state != "available":
		return
	var probe := FileAccess.open(_exe + ".new", FileAccess.WRITE)
	if probe == null:
		_fail("The game can't write to its own folder.")
		return
	probe.close()
	_show("downloading", "Downloading the update...")
	# The signature first: it's tiny, and without it the big download is no use.
	var req := HTTPRequest.new()
	req.timeout = 20
	req.body_size_limit = MAX_SIGNATURE
	add_child(req)
	req.request_completed.connect(func(result, code, _headers, body):
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
			_fail("The update's signature couldn't be downloaded.")
			return
		_signature = body
		_download_game())
	if req.request(_sig_url, [AGENT]) != OK:
		req.queue_free()
		_fail("The download couldn't start.")


func _download_game() -> void:
	_download = HTTPRequest.new()
	_download.download_file = _exe + ".new"
	_download.use_threads = true
	add_child(_download)
	_download.request_completed.connect(_on_downloaded)
	if _download.request(_url, [AGENT]) != OK:
		_fail("The download couldn't start.")
		return
	_percent = -1


# Always the fixed GitHub address, never anything the release info says.
func _open_page() -> void:
	print("[updater] opening the download page")
	if not _testing:
		OS.shell_open(PAGE_URL)
	if state == "available":
		_show(state, button_text, "Download it there, then replace this game file with the new one.")


func _process(_delta: float) -> void:
	if state != "downloading" or _download == null or _size <= 0:
		return
	var percent := int(100.0 * _download.get_downloaded_bytes() / _size)
	if percent != _percent:
		_percent = percent
		_show("downloading", "Downloading the update... %d%%" % clampi(percent, 0, 100))


func _fail(reason: String) -> void:
	if _download:
		_download.queue_free()
		_download = null
	DirAccess.remove_absolute(_exe + ".new")
	print("[updater] failed: " + reason)
	_show("failed", "Open the download page", reason + " You can get version %s from the download page instead." % latest)


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_download.queue_free()
	_download = null
	var incoming := _exe + ".new"
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("The download didn't finish.")
		return
	# Nothing gets run unless it's exactly what the release signed.
	if not signature_ok(_key, latest, ASSETS[OS.get_name()], incoming, _signature):
		_fail("The download didn't match its signature, so it wasn't installed.")
		return
	var old := _exe + ".old"
	DirAccess.remove_absolute(old)
	if DirAccess.rename_absolute(_exe, old) != OK:
		_fail("The game file couldn't be replaced.")
		return
	if DirAccess.rename_absolute(incoming, _exe) != OK:
		DirAccess.rename_absolute(old, _exe)
		_fail("The game file couldn't be replaced.")
		return
	if OS.get_name() == "Linux":
		FileAccess.set_unix_permissions(_exe, 493)   # rwxr-xr-x: mark it as a program
	print("[updater] installed version %s, restarting" % latest)
	if OS.create_process(_exe, _restart_args()) == -1:
		_show("restarting", "Updated", "Version %s is installed. Close the game and start it again." % latest)
		return
	_show("restarting", "Restarting...")
	get_tree().quit()


# Start the new version the way this one was started. Godot doesn't hand back
# the options it used itself, so the one that matters (no window) is put back.
func _restart_args() -> PackedStringArray:
	var args := OS.get_cmdline_args()
	if DisplayServer.get_name() == "headless" and not args.has("--headless"):
		args.append("--headless")
	var user_args := OS.get_cmdline_user_args()
	if not user_args.is_empty() and not args.has("--"):
		args.append("--")
		args.append_array(user_args)
	return args
