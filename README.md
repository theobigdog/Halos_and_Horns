# Halos & Horns

A free, non-commercial prop-hunt game: demons possess everyday objects to hide, angels hunt them down.
Passion project, inspired by Witch It.

## Status: version 0.5.5, Creative mode, Godot 4.7

One small test map (the Playground), placeholder shapes for everything, and Creative mode for building your own.

- **Creative (build maps):** from the main menu. Hold right mouse to look around, WASD to fly (Space/E up, Q down, Shift faster). Pick a piece on the left (blocks, cylinders, every prop, bouncies, the shrine, the angel and demon starts) and click in the world to place it. Click a piece to select it; press on it and drag to move it (it slides over whatever is under the cursor, so you can drag things onto roofs), or use G move, R rotate, T resize; while doing that, X / Y / Z keep it to one axis, L switches between the map's axes and the piece's own, and holding Alt turns snapping off. Ctrl+D copies, Delete removes, F flies to it, Ctrl+Z / Ctrl+Y undo and redo. The right-hand panel takes exact numbers; 0, 0, 0 is the middle of the map. Save, then **Test play** to run a round on it, and Esc → Back to Creative to keep building.
- **Maps** are plain data files (no code, so a map can't do anything but be a map), saved in your maps folder (Creative has a button that opens it). The host picks the map in the lobby; everyone who joins gets it automatically.

- **Practice:** single player. The angel side hunts 3 test demons (they hop and taunt so you can find them); the demon side is a sandbox for possessing props.
- **Online:** one player hosts, friends join with a five-letter room code (no port forwarding), or by address. Mobification rules: caught demons are redeemed and switch to the angels. About one angel per three players.
- **Skills:** pick 2 per side on the main menu or in the lobby. Angels: Flying Dash (dash where you look or the way your keys point, up into the air too; you keep the momentum until you turn: wide turns cost a little, a quick 180 or a strafe kills it), Alarm Cherub (thrown), Vacuum Orb, Holy Leap (steer it in the air; press its key again mid-air to Cloud Stomp, which hurts every demon within 6 m of where you land: most in the middle, up to double from high up; having it picked also makes all your ordinary jumps higher and easier to steer), Holy Scripture (a heavy book, big holy damage), Holy Kick (boot a demon away). Demons: Possess, Fly, Teleport (to your crosshair, up to 20 m; expensive), Minion (a decoy that quietly appears where you aim, looking like you, or like some prop from the map if you're disguised; hold its key to steer it to the ground under your crosshair; it moves like a real player, hits on it look and sound real, but it pops after a hit or two), Hellfire (costs Hatred; angels in the fire are slowed and their blessings burn away), Fear (a hellish shriek: angels within 10 m who can see you panic for 2 s, scattering away from you with their aim shaking all over; 55 Hatred, 15 s cooldown).
- **Demons** can **transform** into a copy of any prop (click), or with skills **become** the real one (Possess) and **fly** (hold the key: you rise while Hatred lasts, gravity brings you down; no fall damage).
- The Alarm Cherub just hovers there tooting its little horn until a demon comes close; then it blasts the horn and shows its detection bubble. Shoot it with a blessing to send it flying down a hallway.
- **Power-ups:** angels drop demon power-ups as they go (more often with more players and the more the demons move about): Hatred Surge, Fire Burst, Invisibility (6.5 s, angels get no trace of you), Unholy Mending (+50% of your starting health per pickup, up to 150%; turns up most often). Each team only ever sees its own team's power-ups. Every redeemed demon drops an angel power-up, and an angel who hasn't found or hit anyone for 30 s gets one dropped nearby: Cherub Sense (a little cherub dangles over your head, and you go off like an Alarm Cherub near demons; your teammates see the cherub too, demons don't), Quick Blessings, Quick Skills, Endless Sprint.
- **Naughtiness pays:** demons earn Hatred when angels roast in their fire, when their minion soaks a hit, and for taunting right under an angel's nose.
- **Bouncies:** springy pads that fling anyone about 8 m up. Blue ones are part of the map; gold ones work once per round.
- **Ledge grab:** angels in the air who push into a wall whose top they could reach pull themselves up onto it.
- **Controls screen:** every action can be rebound to any key or mouse button (main menu or Esc menu).
- **The shrine:** one per map (the stone dais with the floating half-gold, half-red crystal and a SHRINE sign), the only place to swap skills mid-round. Press G there; a swap takes 3 seconds in total, you can't move while at it, demons have to leave their prop first, and the shrine flares up so everyone knows someone is there. Fresh skills start on cooldown.
- **No hiding forever in silence:** demons can sit still as long as they like (they never get kicked for it), but a demon that hasn't moved for 20 seconds during the hunt taunts automatically, and again every 20 seconds after that. You get a 5-second warning first, and taunting on your own resets the clock.
- **Chat:** Enter talks to everyone, Backspace to your team only. Everyone is told who redeemed whom, and who the last demon standing is.
- Every prop form has its own health and speed: small = fragile but quick, big = tanky but slow. Your health bar shows how much is left; the number shows real hit points for your current form.

## Playing (Windows)

Download `HalosAndHorns.exe` from the [Releases page](https://github.com/theobigdog/halos_and_horns/releases) and run it. Nothing to install.
Windows may warn "Windows protected your PC" because the game isn't signed; click **More info**, then **Run anyway**.

## Playing (Linux)

Download `HalosAndHorns.x86_64` from the [Releases page](https://github.com/theobigdog/halos_and_horns/releases). Nothing to install, but Linux needs to be told the file is a program before it will run it:

```
chmod +x HalosAndHorns.x86_64
./HalosAndHorns.x86_64
```

(Or in your file manager: right-click the file → Properties → Permissions → allow executing, then double-click it.)

Windows and Linux players can play together.

## Updating

When a newer version is out, the main menu shows an **Update to version ...** button. Click it and the game downloads the new version, checks it, replaces itself and restarts. If the update can't be checked or installed (say, the game sits in a folder it isn't allowed to change), the button opens the download page instead: download the new file there and replace your old one with it.

**How updates are checked:** every release is signed. The release workflow signs each build with a private key kept as a GitHub secret, and the game carries the matching public key. The signature covers the version number, the file name and the file's exact fingerprint, so the game only installs the very file that was signed for that version: not a swapped or damaged file, and not an older build passed off as a newer one. Anything that doesn't check out is never run. (Versions 0.4 to 0.5.2 checked downloads only against a fingerprint that came from the same place as the file; that's why self-updating was off from 0.5.3 until signing came in.)

What signing doesn't cover: someone who takes over the GitHub account could change the workflow and have it sign their file too. Keeping that account safe (two-factor login) is what keeps updates safe.

Making a release (developers): publish a GitHub release tagged like `v0.4.1`. The tag is the version: the build stamps it into the game, so there is no version number to change in the source. Run from source, the game calls itself version "dev". The workflow signs the builds a few minutes later; that needs the `UPDATE_SIGNING_KEY` secret, made once with `bash tools/make_update_key.sh` (which also writes the public key into `scripts/update_key.gd`, to commit). Without it, releases still work, but games only offer the download page.

## Hosting and joining

**Hosting:** click **Host a game**. The lobby shows a five-letter **room code** (it's also copied, so you can paste it straight into Discord). Pick the hiding and hunting times (and, if you like, a time after which idle angels get kicked; you can also kick someone by hand), then click **Start round** once at least 2 players are in. No router setup is needed: games go through a small relay server (see below).

**Joining:** type the room code, click **Join a game**. Everyone needs exactly the same version as the host; anything else is turned away with a message saying which version to get.

**Without the relay** (same Wi-Fi, or if the relay is down): the host clicks **Host directly** instead, and the lobby shows the addresses to use. Friends type the address (instead of a code) and click **Join a game**.
- Friends on the same Wi-Fi use the "same house" address. That needs no setup.
- Friends over the internet use your internet address, which needs **UDP port 7777 forwarded** on your router to your PC (the Port box changes it). Windows will also ask to allow the game through the firewall: allow it. On Linux, if you run a firewall, allow UDP port 7777 yourself.

### The relay server

Room codes work through [game-relay](https://github.com/drewburr-labs/game-relay), a relay Drew runs at `relay.drewburr.com:24680` that any game can use. The host opens a room, friends join it with the code, and the relay passes packets between them, so nobody forwards ports and nobody sees anyone else's IP address. It only passes bytes along and never reads them: the host is still the referee, and everything below about fairness works the same way.
- `relay/` is a copy of the relay's scripts at the tag in `relay/VERSION`. Don't edit them here: `tools/update_relay.sh <tag>` moves them to a newer release (`--check` says whether they still match). `scripts/relay_peer.gd` is what lets Godot's multiplayer run through the relay.
- Limits: one packet can be at most 256 KB (maps are a few KB). The relay can't force someone out of a room, so a kick makes the host ignore that player and tells their game to leave.
- From the command line (after `--`): `--host-relay` hosts through the relay, `--join=CODE` joins by code (or `--join=ADDRESS` directly), `--relay=HOST[:PORT]` uses a different relay, say one running on this PC: `godot --headless -s res://tests/run_relay.gd -- --port=24680`.

## Playing from the source (developers)

1. Download **Godot 4.7.2** (standard, *not* .NET): https://godotengine.org/download/archive/4.7.2-stable/
2. Open Godot, click **Import**, pick `project.godot`, press **F5**.
3. To build the game yourself: Editor → Manage Export Templates → Download, then Project → Export → Windows or Linux. Either one can be built from either operating system.

Both builds are also made automatically: publishing a release on GitHub runs [the release builds workflow](.github/workflows/release-builds.yml), which attaches `HalosAndHorns.exe` and `HalosAndHorns.x86_64` to that release a few minutes later.

## Controls

| Key | Angel | Demon |
| --- | --- | --- |
| WASD / Space | Move / jump | Move / jump |
| Shift | Run (uses sprint stamina) | Run (uses sprint stamina) |
| Ctrl | Sneak | Sneak |
| 1 | Random taunt | Random taunt |
| 2 | Signature taunt | Signature taunt |
| Left click | Throw a blessing (hold to keep throwing; uses blessing stamina) | Transform into a copy of the outlined prop |
| Hold left click | | Back to demon form |
| Q | Skill 1 | Skill 1 |
| Right click | Skill 2 | Skill 2 |
| F | Melee | |
| (hold the key) | | Fly, if it's one of your skills: rise while held, fall when let go |
| Mouse | Turn (hold **Alt** to look around without turning) | The camera swings around you (hold **Shift** and your body or prop turns with the view) |
| T | First/third person | First/third person |
| B | Change blessing type (testing) | |
| G | Swap skills (at the shrine) | Swap skills (at the shrine, in demon form) |
| Enter / Backspace | Chat to everyone / team chat (online; the host can type /kick Name) | Chat to everyone / team chat (online) |
| F1 | Movement tuning panel | Movement tuning panel |
| Esc | Menu | Menu |
| Tab (hold) | Roster: both teams, ping, skills | Roster: both teams, ping, skills |
| F2 / R / Enter | Practice only: switch side / restart / skip the hiding wait | |

## How online play stays fair

The host is the referee. It decides every hit (other players' throws are only visuals on their own screens), checks every movement for speed hacks and out-of-bounds tricks and snaps cheaters back, mirrors blessing stamina and Hatred (flying longer than your Hatred allows, or floating without flying, drops you to the ground), checks every skill against your loadout and cooldowns, and limits taunt spam. Because everyone sees other players a split second in the past, a throw that hits on the thrower's screen still counts: the host checks it was a real throw, that the hit lies on its flight path with no wall in between, and that the demon really was there a moment ago. Only angels receive names, and only their fellow angels', so no game ever knows who a disguised demon is (not even another demon's).

## Automated tests

- `godot --headless -s res://tests/test_gameplay.gd`: practice mode, movement, stamina, taunts.
- `godot --headless -s res://tests/test_skills.gd`: flying, possess vs transform, per-form health and speed, every angel tool.
- `GODOT=godot tests/test_multiplayer.sh`: plays a whole 5-player online match with bots, including a cheater, and checks the results and that no names leak. With `RELAY=1` it plays the same match through a relay server it runs on this computer.
- `GODOT=godot tests/test_updater.sh`: exports builds with a test key and checks the updater only installs a properly signed newer version, restarting into it, and refuses (without touching the game file) downloads signed with another key, changed after signing, or signed for another version; unsigned releases and builds without a key only get the download page (Linux only).

## License

Free forever, never for profit. Code: PolyForm Noncommercial 1.0.0. Art and sound: CC BY-NC-SA 4.0. See [LICENSE.md](LICENSE.md).
