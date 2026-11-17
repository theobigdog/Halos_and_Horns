#!/usr/bin/env bash
# Automated test of the updater (scripts/updater.gd), Linux only.
# Exports real builds of the game, stamped with versions the way the release
# workflow stamps them and carrying a test signing key, serves releases from a
# stand-in for GitHub on this computer, and checks that the game:
#   1. without a key of its own, only offers the download page, downloading nothing,
#   2. does the same for a release that has no signature,
#   3. refuses a download signed with some other key,
#   4. refuses a download that isn't the file that was signed,
#   5. refuses a signature made for a different version (an old build passed off as new),
#   6. otherwise replaces itself with the newer build and restarts into it,
#   7. and leaves the game file alone, with nothing left behind, every time it refuses.
# Needs Godot with its Linux debug export template installed, python3 and openssl.
# Usage: GODOT=/path/to/godot tests/test_updater.sh
set -u
GODOT="${GODOT:-godot}"
PORT="${PORT:-8765}"
FILE=HalosAndHorns.x86_64
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"
GAME="$OUT/install/$FILE"
SERVE="$OUT/serve"
failures=0

check() {   # check "what" command...
	local what="$1"; shift
	if "$@" >/dev/null 2>&1; then echo "PASS  $what"; else echo "FAIL  $what"; failures=$((failures + 1)); fi
}

cleanup() {
	pkill -f "$OUT/install/" 2>/dev/null
	pkill -f "$OUT/nokey/" 2>/dev/null
	[ -n "${SERVER:-}" ] && kill "$SERVER" 2>/dev/null
	rm -rf "$OUT"
}
trap cleanup EXIT

sha() { sha256sum "$1" | cut -d' ' -f1; }

# A test key, standing in for the real one (whose private half only GitHub has).
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$OUT/key.pem" 2>/dev/null
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$OUT/other.pem" 2>/dev/null

# Export a copy of the project as the given version, with the test key or none.
build() {   # build <folder> <version> <key|nokey>
	local src="$OUT/src-$1"
	mkdir -p "$src" "$OUT/$1"
	(cd "$ROOT" && git ls-files -co --exclude-standard -z | xargs -0 cp --parents -t "$src")
	sed -i "s|^config/version=.*|config/version=\"$2\"|" "$src/project.godot"
	if [ "$3" = key ]; then
		printf 'extends RefCounted\n\nconst PEM := """%s\n"""\n' "$(openssl pkey -in "$OUT/key.pem" -pubout)" > "$src/scripts/update_key.gd"
	fi
	"$GODOT" --headless --path "$src" --export-debug Linux "$OUT/$1/$FILE" > "$OUT/$1.export.log" 2>&1
	chmod +x "$OUT/$1/$FILE" 2>/dev/null
	test -s "$OUT/$1/$FILE"
}

# Sign a file the way the release workflow does.
sign() {   # sign <key> <version> <file> <signature out>
	printf 'Halos & Horns update\nversion %s\nfile %s\nsha256 %s\n' "$2" "$FILE" "$(sha "$3")" \
		| openssl dgst -sha256 -sign "$1" -out "$4"
}

# What GitHub's "latest release" answer looks like, as far as the updater reads it.
release() {   # release <tag> <game file in serve/> [signature file in serve/]
	local sig=""
	[ -n "${3:-}" ] && sig=", {\"name\": \"$FILE.sig\", \"browser_download_url\": \"http://127.0.0.1:$PORT/$3\"}"
	cat > "$SERVE/latest.json" <<-EOF
	{"tag_name": "$1", "assets": [{"name": "$FILE", "size": $(stat -c %s "$SERVE/$2"),
	  "browser_download_url": "http://127.0.0.1:$PORT/$2"}$sig]}
	EOF
}

# Run a game until its log says something (or it quits, or time runs out).
run_until() {   # run_until <game> <log> <text to wait for> <seconds>
	"$1" --headless -- "--update-api=http://127.0.0.1:$PORT/latest.json" --update-click > "$2" 2>&1 &
	local pid=$!
	for _ in $(seq $(($4 * 5))); do
		grep -q "$3" "$2" 2>/dev/null && break
		kill -0 "$pid" 2>/dev/null || break
		sleep 0.2
	done
	sleep 0.5
	kill "$pid" 2>/dev/null
	wait "$pid" 2>/dev/null
}

downloads() { grep -c "GET /$1 " "$OUT/server.log"; }

untouched() {   # the game file is as it was, with nothing next to it
	test "$(sha "$GAME")" = "$OLD" && test "$(ls "$OUT/install" | wc -l)" -eq 1
}

echo "Exporting three builds (this takes a few minutes)..."
check "the current version exports, with the test key" build install "1.0.0" key
check "a newer version exports" build serve "99.0.0" key
check "a build without a key exports" build nokey "1.0.0" nokey
OLD="$(sha "$GAME")"
NEW="$(sha "$SERVE/$FILE")"
check "the builds differ" test "$OLD" != "$NEW"

sign "$OUT/key.pem" "99.0.0" "$SERVE/$FILE" "$SERVE/good.sig"
sign "$OUT/other.pem" "99.0.0" "$SERVE/$FILE" "$SERVE/stranger.sig"
sign "$OUT/key.pem" "98.0.0" "$SERVE/$FILE" "$SERVE/oldversion.sig"
cp "$SERVE/$FILE" "$SERVE/tampered" && printf 'x' >> "$SERVE/tampered"

(cd "$SERVE" && exec python3 -m http.server "$PORT" --bind 127.0.0.1) > "$OUT/server.log" 2>&1 &
SERVER=$!
sleep 1

# 1. No key in this build: the download page only.
release "v99.0.0" "$FILE" good.sig
run_until "$OUT/nokey/$FILE" "$OUT/nokey.log" "opening the download page" 20
check "a build without a key notices the newer version" grep -q "version 99.0.0 is available (download page only)" "$OUT/nokey.log"
check "...and only opens the download page" grep -q "updater\] opening the download page" "$OUT/nokey.log"
check "...downloading nothing" test "$(downloads "$FILE")" -eq 0

# 2. A release without a signature: the download page only.
release "v99.0.0" "$FILE"
run_until "$GAME" "$OUT/unsigned.log" "opening the download page" 20
check "an unsigned release is offered as a download page only" grep -q "version 99.0.0 is available (download page only)" "$OUT/unsigned.log"
check "...downloading nothing" test "$(downloads "$FILE")" -eq 0
check "...and leaving the game alone" untouched

# 3-5. Bad signatures: downloaded, checked, refused.
for bad in "stranger.sig:$FILE:signed with another key" \
		"good.sig:tampered:changed after it was signed" \
		"oldversion.sig:$FILE:signed as a different version"; do
	IFS=: read -r sig file what <<< "$bad"
	release "v99.0.0" "$file" "$sig"
	run_until "$GAME" "$OUT/$sig-$file.log" "updater\] failed" 30
	check "a download $what is refused" grep -q "updater\] failed: The download didn't match its signature" "$OUT/$sig-$file.log"
	check "...and the game file is untouched, with nothing left behind" untouched
done

# 6. The real thing: installed, restarted, and not offered again.
release "v99.0.0" "$FILE" good.sig
timeout 60 "$GAME" --headless -- "--update-api=http://127.0.0.1:$PORT/latest.json" --update-click > "$OUT/good.log" 2>&1
check "a properly signed update installs, and the old game quits by itself" test $? -eq 0
check "...the game file is now the new version" test "$(sha "$GAME")" = "$NEW"
check "...and can still be run" test -x "$GAME"
sleep 3
check "the new version is running" pgrep -f "$OUT/install/"
check "...and has removed the old file" test ! -e "$GAME.old" -a ! -e "$GAME.new"
check "...and doesn't offer the update again" test "$(grep -c 'is available' "$OUT/good.log")" -eq 1
check "no script errors" bash -c "! grep -q 'SCRIPT ERROR' '$OUT'/*.log"

echo
if [ "$failures" -eq 0 ]; then
	echo "ALL PASSED: 0 failure(s)"
else
	echo "$failures FAILURE(S)"
	tail -n 20 "$OUT"/*.log
fi
exit "$failures"
