# Halos & Horns

A free, non-commercial prop-hunt game: demons possess everyday objects to hide, angels hunt them down.
Passion project, inspired by Witch It.

## Status: Phase 1 prototype

One small test map, single player, placeholder shapes for everything.

- **Angel side (default):** wait out the 30-second hiding period, then find and catch 3 bot demons disguised as props within 3 minutes. They fidget once in a while; watch for it. (They hop every few seconds during testing so they're easy to find.)
- **Demon side:** a sandbox for possessing props. No angel AI yet; real hunting comes with multiplayer in Phase 2.

## How to play it

1. Download **Godot 4.3** (the standard version, *not* .NET) from https://godotengine.org/download/archive/4.3-stable/
   It's a single .exe, no installer. Put it anywhere.
2. Open Godot, click **Import**, and pick `project.godot` in this folder.
3. Press **F5** (or the play button, top right).

## Controls

| Key | Angel | Demon |
| --- | --- | --- |
| WASD / Space | Move / jump | Move / jump |
| Shift | Run | Run |
| Ctrl | Sneak (won't walk off edges) | Sneak (won't walk off edges) |
| Left click | Throw a blessing (hold to keep throwing) | Possess the outlined prop under the crosshair |
| B | Change blessing type (testing) | |
| Hold left click | | Back to demon form |
| T | First/third person | First/third person |
| Tab | Switch to demon | Switch to angel |
| Enter | Skip the hiding wait (testing) | |
| R | Restart round | Restart round |
| Esc | Free the mouse (click to grab it again) | |

## Automated test

From this folder: `godot --headless -s res://tests/test_gameplay.gd`
Plays an angel round to a win and checks demon possession.

## License

Free forever, never for profit. Code: PolyForm Noncommercial 1.0.0. Art and sound: CC BY-NC-SA 4.0. See [LICENSE.md](LICENSE.md).
