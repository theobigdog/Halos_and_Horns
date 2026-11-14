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

"$GODOT" --headless -- --host --name=Theo --autobot --autostart=5 --hide=4 --hunt=150 --quit-after-round > "$OUT/host.log" 2>&1 &
sleep 3
for n in Wife Brother Squirrel Oddy; do
	extra=""
	[ "$n" = "Oddy" ] && extra="--cheat=teleport"
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
check "only the real cheat was flagged (no false alarms)" "[ \$(grep -c '^\\[host\\] blocked' '$OUT/host.log') -le 1 ]"
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
