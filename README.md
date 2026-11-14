# Halos & Horns

A free, non-commercial prop-hunt game: demons possess everyday objects to hide, angels hunt them down.
Passion project, inspired by Witch It.

## Status: version 0.3.1, Fly is a skill

One small test map, placeholder shapes for everything.

- **Practice:** single player. The angel side hunts 3 test demons (they hop and taunt so you can find them); the demon side is a sandbox for possessing props.
- **Online:** one player hosts, friends join by address. Mobification rules: caught demons are redeemed and switch to the angels. About one angel per three players.
- **Skills:** pick 2 per side on the main menu or in the lobby. Angels: Grappling Hook, Alarm Chicken, Vacuum Orb, Holy Leap. Demons: Possess, Fly (more coming).
- **Demons** can **transform** into a copy of any prop (click), or with skills **become** the real one (Possess) and **fly** (hold the key: you rise while Hatred lasts, gravity brings you down; no fall damage).
- The Alarm Chicken is just a chicken until a demon comes close; then it squawks and shows its detection bubble. Shoot it with a blessing to send it skidding down a hallway.
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

## Hosting and joining

**Hosting:** click **Host a game**. The lobby shows the addresses friends should use. Click **Start round** once at least 2 players are in.
- Friends on the same Wi-Fi use the "same house" address. That needs no setup.
- Friends over the internet use your internet address, which needs **UDP port 7777 forwarded** on your router to your PC. Windows will also ask to allow the game through the firewall: allow it. On Linux, if you run a firewall, allow UDP port 7777 yourself.

**Joining:** type the host's address, click **Join a game**. Everyone needs the same version.

## Playing from the source (developers)

1. Download **Godot 4.3** (standard, *not* .NET): https://godotengine.org/download/archive/4.3-stable/
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
| T | First/third person | First/third person |
| B | Change blessing type (testing) | |
| F1 | Movement tuning panel | Movement tuning panel |
| Esc | Menu | Menu |
| Tab (hold) | Roster: both teams, ping, skills | Roster: both teams, ping, skills |
| F2 / R / Enter | Practice only: switch side / restart / skip the hiding wait | |

## How online play stays fair

The host is the referee. It decides every hit (other players' throws are only visuals on their own screens), checks every movement for speed hacks and out-of-bounds tricks and snaps cheaters back, mirrors blessing stamina and Hatred (flying longer than your Hatred allows, or floating without flying, drops you to the ground), checks every skill against your loadout and cooldowns, and limits taunt spam. Each player only receives names for their own team, so an angel's game never knows who a disguised demon is.

## Automated tests

- `godot --headless -s res://tests/test_gameplay.gd`: practice mode, movement, stamina, taunts.
- `godot --headless -s res://tests/test_skills.gd`: flying, possess vs transform, per-form health and speed, every angel tool.
- `GODOT=godot tests/test_multiplayer.sh`: plays a whole 5-player online match with bots, including a cheater, and checks the results and that no names leak.

## License

Free forever, never for profit. Code: PolyForm Noncommercial 1.0.0. Art and sound: CC BY-NC-SA 4.0. See [LICENSE.md](LICENSE.md).
