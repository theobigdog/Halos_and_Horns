#!/usr/bin/env bash
# Plays a full online match with 5 copies of the game on this computer, no humans:
# a host plus 4 joined players, all driven by the autobot. One player tries to
# teleport out of bounds. Passes if the round ends with every demon caught, every
# player saw only their own team's names, and the host blocked the cheat.
#
# Usage: GODOT=/path/to/godot tests/test_multiplayer.sh
set -u
GODOT="${GODOT:-godot}"
OUT="$(mktemp -d)"
cd "$(dirname "$0")/.."

"$GODOT" --headless -- --host --name=Theo --autobot --autostart=5 --hide=14 --hunt=150 --quit-after-round \
	--roles=Theo:demon,Wife:angel,Brother:demon,Squirrel:angel,Oddy:demon > "$OUT/host.log" 2>&1 &
sleep 3
for n in Wife Brother Squirrel Oddy; do
	extra=""
	[ "$n" = "Oddy" ] && extra="--cheat=teleport,fly"
	[ "$n" = "Wife" ] && extra="--skills=chicken,vacuum"
	[ "$n" = "Squirrel" ] && extra="--skills=grapple,vacuum"
	timeout 240 "$GODOT" --headless -- --join=127.0.0.1 --name=$n --autobot --quit-after-round $extra > "$OUT/$n.log" 2>&1 &
	sleep 0.5
done
wait

fail=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }

check "round started with 5 players" "grep -q 'round started: 2 angel(s), 3 demon(s)' '$OUT/host.log'"
end_msg=$(grep -m1 -oE "round over: .*" "$OUT/host.log" | sed 's/round over: //')
check "round ended ($end_msg)" "[ -n \"$end_msg\" ]"
check "at least one demon was caught" "grep -q 'was caught' '$OUT/host.log'"
for n in Wife Brother Squirrel Oddy; do
	check "$n saw the same result as the host" "grep -qF \"round over: $end_msg\" '$OUT/$n.log'"
	if grep -q "\\[host\\] $n was caught" "$OUT/host.log"; then
		check "$n was caught and switched to the angel side" "grep -q 'now playing as angel' '$OUT/$n.log'"
	fi
done
check "flying without Hatred was caught" "grep -q 'blocked Oddy: flying without enough Hatred' '$OUT/host.log'"
check "no false alarms (only Oddy was flagged)" "! grep '^\\[host\\] blocked' '$OUT/host.log' | grep -qv 'blocked Oddy'"
check "demons flew" "grep -q 'flying' '$OUT/Brother.log'"
check "a demon possessed a real prop" "grep -q 'a demon possessed a' '$OUT/host.log'"
check "an angel dropped an Alarm Chicken" "grep -q 'chicken dropped' '$OUT/host.log'"
check "an angel threw a Vacuum Orb" "grep -q 'vacuum orb' '$OUT/host.log'"
check "an angel fired a grappling hook" "grep -q 'used grapple' '$OUT/Squirrel.log'"
check "the roster shows chosen skills" "grep -q 'Wife(angel,[0-9]*ms,Alarm Chicken+Vacuum Orb)' '$OUT/Brother.log'"
check "out-of-bounds teleport was blocked" "grep -q 'blocked Oddy: out of bounds' '$OUT/host.log'"
x=$(grep -oE 'after cheat, position x = -?[0-9.]+' "$OUT/Oddy.log" | grep -oE -- '-?[0-9.]+$')
check "cheater was snapped back inside the map (x=$x)" "awk -v x=\"$x\" 'BEGIN { exit !(x != \"\" && x < 28.5 && x > -28.5) }'"
# Name leaks: a player may only ever see names of their own team.
leaks=$(grep -h "names I can see" "$OUT"/*.log | awk '{
	me=$4; sub(",", "", me)
	for (i = 1; i <= NF; i++) if ($i ~ /^(angel|demon)=/) {
		split($i, kv, "="); nm = kv[2]; sub(",$", "", nm)
		if (kv[1] != me && nm != "<hidden>") print
	}
}')
check "no player ever saw an enemy's name" "[ -z \"$leaks\" ]"
check "name checks actually ran" "[ \$(grep -h 'names I can see' '$OUT'/*.log | wc -l) -ge 5 ]"
for n in Wife Brother Squirrel Oddy; do
	line=$(grep -m1 "roster:" "$OUT/$n.log")
	check "$n's Tab roster lists all 5 players" "[ \$(echo \"$line\" | grep -oE '(Theo|Wife|Brother|Squirrel|Oddy)\\((angel|demon),' | wc -l) -eq 5 ]"
	check "$n's ping is measured" "echo \"$line\" | grep -qE 'my ping [0-9]+'"
done
check "no player script errors" "! grep -q 'SCRIPT ERROR' '$OUT'/*.log"

if [ $fail -eq 0 ]; then echo "ALL PASSED"; else echo "FAILED (logs in $OUT)"; fi
exit $fail
