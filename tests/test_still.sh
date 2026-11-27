#!/bin/bash
# Demons can sit still forever, but every 30 s (Custom rules: still_taunt) without moving during the hunt they taunt anyway.
GODOT=${GODOT:-godot}
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
"$GODOT" --headless -- --host --name=Abe --autobot --still --autostart=3 --hide=3 --hunt=45 --quit-after-round \
	--roles=Abe:demon,Ava:demon,Cal:angel > "$OUT/host.log" 2>&1 &
sleep 3
for n in Ava Cal; do
	timeout 110 "$GODOT" --headless -- --join=127.0.0.1 --name=$n --autobot --still --quit-after-round > "$OUT/$n.log" 2>&1 &
	sleep 1
done
wait
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=$((fails+1)); fi; }
check "the host's own still demon taunted" "grep -q 'Abe sat still too long: forced taunt' '$OUT/host.log'"
check "a joined still demon taunted" "grep -q 'Ava sat still too long: forced taunt' '$OUT/host.log'"
check "...and was told" "grep -q 'forced to taunt' '$OUT/Ava.log'"
check "only once in 45 s of hunting (every 30 s)" "[ \$(grep -c 'Ava sat still too long' '$OUT/host.log') -eq 1 ]"
check "nobody was kicked" "! grep -q 'kicked' '$OUT/host.log'"
check "no script errors" "! grep -q 'SCRIPT ERROR' '$OUT'/*.log"
if [ $fails -eq 0 ]; then echo "ALL PASSED"; else echo "FAILED (logs in $OUT)"; fi
