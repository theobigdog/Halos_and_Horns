#!/bin/bash
# Building together: a host and two joiners in Creative on one map, one of them cheating
# (see tests/build_bot.gd). Everyone must end up with the same map, the junk refused.
GODOT=${GODOT:-godot}
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
"$GODOT" --headless -- --host --name=Abe --buildbot=host --map=res://tests/test_map.json > "$OUT/host.log" 2>&1 &
sleep 3
timeout 90 "$GODOT" --headless -- --join=127.0.0.1 --name=Ava --buildbot=ava > "$OUT/Ava.log" 2>&1 &
sleep 1
timeout 90 "$GODOT" --headless -- --join=127.0.0.1 --name=Cid --buildbot=cheat > "$OUT/Cid.log" 2>&1
wait
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=$((fails+1)); fi; }
final() { grep -o 'final [0-9a-f]*' "$OUT/$1.log" | head -1; }
check "everyone went into Creative together" "grep -q 'host is building' '$OUT/host.log' && grep -q 'ava is building' '$OUT/Ava.log' && grep -q 'cheat is building' '$OUT/Cid.log'"
check "everyone ends up with the same map ($(final host))" "[ -n \"\$(final host)\" ] && [ \"\$(final host)\" = \"\$(final Ava)\" ] && [ \"\$(final host)\" = \"\$(final Cid)\" ]"
check "the host can't grab a piece Ava has selected" "grep -q 'tried to grab .*selected=-1' '$OUT/host.log'"
check "Ava moved the host's block once it was free" "grep -q 'magenta block at \[8.0, 1.0, 8.0\]' '$OUT/host.log'"
check "Ava's undo brought her wall back" "grep -q 'undid it: 1 walls' '$OUT/Ava.log' && grep -q 'model/dungeon/wall' '$OUT/host.log'"
check "the cheater couldn't move Ava's claimed crate" "grep -q \"Ava's crate at \[-4\" '$OUT/host.log'"
check "junk was refused: no nukes, one shrine, starts kept" "! grep 'pieces:' '$OUT/host.log' | grep -q nuke && [ \$(grep 'pieces:' '$OUT/host.log' | grep -o 'shrine' | wc -l) -eq 1 ] && grep 'pieces:' '$OUT/host.log' | grep -q angel_spawn"
check "a silly map size was clamped" "grep -q 'size 200' '$OUT/host.log'"
check "flooding and view-only edits were refused" "grep -q 'too fast' '$OUT/host.log' && grep -q 'view-only)' '$OUT/host.log' && grep -q 'Cid is view-only' '$OUT/host.log'"
check "the view-only player's block never appeared" "! grep -q '#123456' '$OUT/host.log' && grep -q 'can_edit=false' '$OUT/Cid.log'"
check "done building: the map is the lobby's map" "grep -q 'lobby map has .* pieces, building=false' '$OUT/host.log' && grep -q 'building ended' '$OUT/Ava.log'"
check "no script errors" "! grep -q 'SCRIPT ERROR' '$OUT'/*.log"
if [ $fails -eq 0 ]; then echo "ALL PASSED"; else echo "FAILED (logs in $OUT)"; fi
