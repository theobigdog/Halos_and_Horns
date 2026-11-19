#!/usr/bin/env bash
# Plays a full online match with 5 copies of the game on this computer, no humans:
# a host plus 4 joined players, all driven by the autobot. One player tries to
# teleport out of bounds. Passes if the round ends with every demon caught, every
# angel saw only fellow angels' names (demons see none), and the host blocked the cheat.
#
# Usage: GODOT=/path/to/godot tests/test_multiplayer.sh
#        RELAY=1 GODOT=... tests/test_multiplayer.sh    the same match through a relay
#                                                       server running on this computer
set -u
GODOT="${GODOT:-godot}"
OUT="$(mktemp -d)"
cd "$(dirname "$0")/.."

HOST_ARG="--host"
NET=""
JOIN="127.0.0.1"
RELAY_PID=""
if [ "${RELAY:-0}" = 1 ]; then
	"$GODOT" --headless -s res://tests/run_relay.gd -- --port=24699 --quit-after=300 > "$OUT/relay.log" 2>&1 &
	RELAY_PID=$!
	sleep 2
	HOST_ARG="--host-relay"
	NET="--relay=127.0.0.1:24699"
fi

"$GODOT" --headless -- $HOST_ARG $NET --name=Abe --autobot --give-sense --autostart=5 --hide=14 --hunt=150 --quit-after-round --skills=possess,fear 	--roles=Abe:demon,Ava:angel,Ben:demon,Cal:angel,Dee:demon > "$OUT/host.log" 2>&1 &
PIDS=($!)
sleep 3
if [ -n "$RELAY_PID" ]; then
	for i in $(seq 20); do
		JOIN=$(grep -m1 -oE '\[room\] code [A-Z0-9]{5}' "$OUT/host.log" | awk '{print $3}')
		[ -n "$JOIN" ] && break
		sleep 0.5
	done
	echo "relay room code: ${JOIN:-none}"
fi
for n in Ava Ben Cal Dee; do
	extra=""
	[ "$n" = "Dee" ] && extra="--cheat=teleport,fly --skills=teleport,fly"
	[ "$n" = "Ava" ] && extra="--skills=cherub,vacuum --say=hello_everyone --cheat=claim"
	[ "$n" = "Cal" ] && extra="--skills=dash,leap"
	[ "$n" = "Ben" ] && extra="--skills=fire,minion --sayteam=demons_only_secret"
	timeout 240 "$GODOT" --headless -- --join=$JOIN $NET --name=$n --autobot --quit-after-round $extra > "$OUT/$n.log" 2>&1 &
	PIDS+=($!)
	sleep 0.5
done
# Someone joining mid-round (an angel) must see the props as they are by then.
(sleep 24; timeout 200 "$GODOT" --headless -- --join=$JOIN $NET --name=Late --autobot --lazy --quit-after-round > "$OUT/Late.log" 2>&1) &
PIDS+=($!)
wait "${PIDS[@]}"
[ -n "$RELAY_PID" ] && kill "$RELAY_PID" 2>/dev/null

fail=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }

check "round started with 5 players" "grep -q 'round started: 2 angel(s), 3 demon(s)' '$OUT/host.log'"
end_msg=$(grep -m1 -oE "round over: .*" "$OUT/host.log" | sed 's/round over: //')
check "round ended ($end_msg)" "[ -n \"$end_msg\" ]"
check "at least one demon was caught" "grep -q 'was caught' '$OUT/host.log'"
for n in Ava Ben Cal Dee; do
	check "$n saw the same result as the host" "grep -qF \"round over: $end_msg\" '$OUT/$n.log'"
	if grep -q "\\[host\\] $n was caught" "$OUT/host.log"; then
		check "$n was caught and switched to the angel side" "grep -q 'now playing as angel' '$OUT/$n.log'"
	fi
done
check "flying without Hatred was caught" "grep -q 'blocked Dee: flying without enough Hatred' '$OUT/host.log'"
check "no false alarms (only Dee was flagged)" "! grep '^\\[host\\] blocked' '$OUT/host.log' | grep -qv 'blocked Dee'"
check "demons flew" "grep -q 'flying' '$OUT/Ben.log' '$OUT/Abe.log' '$OUT/Dee.log'"
check "a demon possessed a real prop" "grep -q 'a demon possessed a' '$OUT/host.log'"
check "an angel dropped an Alarm Cherub" "grep -q 'cherub dropped' '$OUT/host.log'"
check "an angel threw a Vacuum Orb" "grep -q 'vacuum orb' '$OUT/host.log'"
check "an angel used the Flying Dash" "grep -q 'used dash' '$OUT/Cal.log'"
if grep -q 'used fire' "$OUT/Ben.log"; then
	check "a demon flung Hellfire" "grep -q 'hellfire lit' '$OUT/host.log'"
fi
check "an angel used Holy Leap" "grep -q 'used leap' '$OUT/Cal.log'"
# (only if the stomp landed before the round ended)
if sed '/round over/q' "$OUT/Cal.log" | grep -q 'used stomp'; then
	check "...and the host handled the Cloud Stomp" "grep -q 'cloud stomp hit' '$OUT/host.log'"
fi
check "the roster shows chosen skills" "grep -q 'Ava(angel,[0-9]*ms,Alarm Cherub+Vacuum Orb)' '$OUT/Ben.log'"
check "out-of-bounds teleport was blocked" "grep -q 'blocked Dee: out of bounds' '$OUT/host.log'"
x=$(grep -oE 'after cheat, position x = -?[0-9.]+' "$OUT/Dee.log" | grep -oE -- '-?[0-9.]+$')
check "cheater was snapped back inside the map (x=$x)" "awk -v x=\"$x\" 'BEGIN { exit !(x != \"\" && x < 28.5 && x > -28.5) }'"
# Name leaks: only angels see names, and only their fellow angels'.
leaks=$(grep -h "names I can see" "$OUT"/*.log | awk '{
	me=$4; sub(",", "", me)
	for (i = 1; i <= NF; i++) if ($i ~ /^(angel|demon)=/) {
		split($i, kv, "="); nm = kv[2]; sub(",$", "", nm)
		if (nm != "<hidden>" && (kv[1] != me || me == "demon")) print
	}
}')
check "no player ever saw a name they shouldn't (enemies, or anyone as a demon)" "[ -z \"$leaks\" ]"
check "angels can see their fellow angels' names" "grep -h 'as angel, names I can see' '$OUT'/*.log | grep -qE 'angel=(Abe|Ava|Ben|Cal|Dee)'"
check "name checks actually ran" "[ \$(grep -h 'names I can see' '$OUT'/*.log | wc -l) -ge 5 ]"
for n in Ava Ben Cal Dee; do
	line=$(grep -m1 "roster:" "$OUT/$n.log")
	check "$n's Tab roster lists all 5 players" "[ \$(echo \"$line\" | grep -oE '(Abe|Ava|Ben|Cal|Dee)\\((angel|demon),' | wc -l) -eq 5 ]"
	# (any roster line: the very first can come before the first ping is back, more so through a relay)
	check "$n's ping is measured" "grep 'roster:' '$OUT/$n.log' | grep -qE 'my ping [0-9]+'"
done
check "global chat reaches the other team" "grep -q '(All) Ava: hello_everyone' '$OUT/Dee.log'"
check "team chat reaches teammates" "grep -q '(Team Only) Ben: demons_only_secret' '$OUT/host.log'"
check "team chat never reaches the other team" "! grep -q 'demons_only_secret' '$OUT/Ava.log' '$OUT/Cal.log'"
# (Whether a hit is counted by the host's own copy of a throw or by the thrower's
# claim depends on timing, so this only checks that real claims aren't refused for
# being off the throw's path or behind walls.)
check "real hit claims aren't refused as impossible" "! grep -E \"refused (Abe|Ben|Cal|Dee)'s hit claim: (not on that throw's path|through a wall)\" '$OUT/host.log'"
check "a made-up hit claim is refused" "grep -q \"refused Ava's hit claim\" '$OUT/host.log'"
check "everyone hears who redeemed whom" "grep -qE '\\[news\\] [A-Za-z]+ redeemed [A-Za-z]+!' '$OUT/Ava.log'"
if [ $(grep -c 'was caught' "$OUT/host.log") -ge 2 ]; then
	check "everyone hears who the last demon is" "grep -q 'LAST demon standing' '$OUT/Cal.log'"
fi
if grep -q 'used minion' "$OUT/Ben.log"; then
	# (A Vacuum Orb or a smite can lock Ben's skills just as he sends it: then the host refuses it, and says so.)
	check "a demon sent out a minion and the host showed it to everyone (or refused it: skills locked)" 		"grep -q -e 'Ben sent out a minion' -e \"refused Ben's minion: skills locked\" '$OUT/host.log'"
fi
if grep -qE '(Ava|Ben|Cal|Dee) sat still too long' "$OUT/host.log"; then
	check "...and that player's game was told" "grep -q 'forced to taunt' '$OUT/Ava.log' '$OUT/Ben.log' '$OUT/Cal.log' '$OUT/Dee.log'"
fi
if grep -q 'BOT Abe: used fear' "$OUT/host.log"; then
	check "Fear: the host scattered the angels near the demon" "grep -qE 'fear: [1-9] angel' '$OUT/host.log'"
	check "...and a scared angel was told" "grep -q 'scared!' '$OUT/Ava.log' '$OUT/Cal.log' '$OUT/Ben.log' '$OUT/Dee.log'"
fi
if grep -qE 'picked up sense' "$OUT/host.log"; then
	check "Cherub Sense: others see the cherub over the angel's head" "grep -q \"cherub over an angel\" '$OUT'/*.log"
fi
if grep -qE 'picked up vanish' "$OUT/host.log"; then
	check "Invisibility power-up: the host hid the demon from the angels" "grep -q ' vanished' '$OUT/host.log'"
fi
if grep -q 'used teleport' "$OUT/Dee.log"; then
	check "Teleport: the host moved the demon" "grep -q 'teleport' '$OUT/host.log'"
fi
if grep -q 'was caught' "$OUT/host.log"; then
	check "a redeemed demon drops an angel power-up" "grep -q 'angel power-up dropped' '$OUT/host.log'"
fi
if grep -q 'now playing as angel' "$OUT/Late.log" 2>/dev/null; then
	check "a mid-round joiner catches up on taken and moved props" "grep -q 'caught up on the props' '$OUT/Late.log'"
fi
if [ -n "$RELAY_PID" ]; then
	check "the match went through the relay (room $JOIN)" "grep -q 'halos-and-horns room $JOIN opened' '$OUT/relay.log'"
fi
if grep -q 'picked up sense\|picked up quick' "$OUT/host.log"; then
	check "a power-up aura shows on other players' screens" "grep -q '\[aura\] angel (own body) shows' '$OUT'/*.log"
fi
check "never an aura on a disguised demon" "! grep '\[aura\]' '$OUT'/*.log | grep -v 'own body'"
check "no player script errors" "! grep -q 'SCRIPT ERROR' '$OUT'/*.log"

if [ $fail -eq 0 ]; then echo "ALL PASSED"; else echo "FAILED (logs in $OUT)"; fi
exit $fail
