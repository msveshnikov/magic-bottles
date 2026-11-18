# AGENTS.md — Magic Bottles (Волшебные бутылочки)

3D water-sort puzzle in Godot 4.7: pour glowing potions between glass bottles until every bottle holds one colour.
Remake of the old HTML/Cordova "Magic Bottles" (removed from this folder; see `decisions.md` for what changed).

## Where everything is

| What | Where |
|---|---|
| Project (Godot 4.7, GL Compatibility) | `C:\My-progs\Godot\watersort` |
| GitHub (public) | https://github.com/msveshnikov/magic-bottles (branch `master`) |
| Downloads | GitHub releases: `MagicBottles.exe`, `MagicBottles.apk` (`releases/latest/download/...`) |
| Live web build | https://severance.lol/8/ |
| Android APK | https://severance.lol/8/MagicBottles.apk — package `com.magicbottles.game`, signed with `~/.android/debug.keystore` (same key as the old Cordova APK, so it updates it) |
| Server folder | `ubuntu@severance.lol:/var/www/severance/8/` (SSH key auth) |
| Old Cordova release keystore | `~/.android/magicbottles-cordova.keystore` + `magicbottles-cordova.txt` (alias `my-key-alias`). Never commit. |
| Godot exe | `C:\Users\msves\OneDrive\Рабочий стол\Godot_v4.7.2-stable_win64.exe` |
| Blender exe | `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe` |
| Bottles, corks, shelf + volume tables | `blender/scripts/build_assets.py` → `assets/models/*.glb`, `assets/models/bottles.json` |
| Levels | `assets/levels/levels.json`, made by `python tools/gen_levels.py` (~70 s) |
| Backgrounds / icon (ChatGPT art) | originals `concept/` (ignored by Godot), game copies `assets/backgrounds/*.jpg`, `assets/ui/` |
| Sounds, music, fonts | `assets/audio`, `assets/fonts` — sources and licences in `assets/CREDITS.md` |
| Suno soundtrack (not downloaded yet) | https://suno.com/song/caa72599-9574-4d42-bc9e-0af93cc82b88 (alt take 7678d6b3-c8de-459c-8869-0fee7696ef49) |
| Save file | `user://save.json` (Windows: `%APPDATA%\Godot\app_userdata\Magic Bottles\`) |
| Autotest output | `renders/game/*.png`, `renders/autotest.log` |
| Builds | `build/windows/MagicBottles.exe`, `build/web/`, `build/android/MagicBottles.apk` |

## Code map

| File | Role |
|---|---|
| `scripts/game.gd` (autoload `Game`) | palette, worlds, levels, save, texts (ru/en), command-line flags |
| `scripts/sfx.gd` (autoload `Sfx`) | sound groups, pour loops, music |
| `scripts/puzzle.gd` | rules, packed-state weighted-A* solver (time-sliced for hints) |
| `scripts/bottle.gd` | one bottle: glass/cork meshes, liquid mesh, layer volumes → shader, slosh, "?" marks |
| `scripts/board.gd` | layout (1–3 rows), taps, pour animation along the volume tables, stream/splash/cork/sparkles, undo, hints, +1 bottle |
| `scripts/main.gd` | screens (title, levels, game, win, stuck, settings), HUD, backdrop + ambient particles, camera fit, tutorial, autotest |
| `scripts/ui_kit.gd` | fonts, buttons, vector icons, stars, panels |
| `shaders/*.gdshader` | liquid, glass, stream, background, sparkles, droplets |

## Rules

Bottles hold 4 units. Tap a bottle, then another: the top run of one colour pours onto the same colour or into an
empty bottle, as much as fits. A bottle with 4 units of one colour gets a cork. Win = every bottle empty or corked.
Hidden layers ("?") show their colour when they reach the top. Stars: 3 at or under par (solver's move count),
2 within par + 30 %, else 1; using the +1 bottle caps at 2.

## Test

```
G="/c/Users/msves/OneDrive/Рабочий стол/Godot_v4.7.2-stable_win64.exe"
"$G" --headless --path . --import
"$G" --path . --quit-after 16000 -- --autotest                       # portrait
"$G" --path . --resolution 1280x720 --quit-after 16000 -- --autotest # landscape (land_*.png)
```
The autotest replays every level's stored solution, shoots all screens, solves level 1 by real taps (tutorial),
checks rejection of an illegal pour, undo, hint, +1 bottle, restart during a pour, stuck detection, solves a
hidden-layer level with fast overlapping taps, and shoots the largest board of every world. Exit code 0 = pass.
Other flags: `-- --level N`, `-- --fresh`, `-- --lang en|ru`.

## Rebuild assets

```
"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup -P blender/scripts/build_assets.py
python tools/gen_levels.py
```

## Build and deploy

```
"$G" --headless --path . --export-release "Windows Desktop" build/windows/MagicBottles.exe
"$G" --headless --path . --export-release "Web" build/web/index.html
"$G" --headless --path . --export-debug "Android" build/android/MagicBottles.apk
scp -o BatchMode=yes build/web/* build/android/MagicBottles.apk ubuntu@severance.lol:/var/www/severance/8/
curl -sI https://severance.lol/8/index.pck
```
The Android preset signs with `~/.android/debug.keystore` via `.godot/export_credentials.cfg` (not in git):
`keystore/debug="C:/Users/msves/.android/debug.keystore"`, user `androiddebugkey`, password `android`.
Bump `version/code` for every APK that must install over an older one.

GitHub release: `"/c/Program Files/GitHub CLI/gh.exe" release create vX.Y build/windows/MagicBottles.exe build/android/MagicBottles.apk --target master --title "Magic Bottles X.Y" --notes-file notes.md`.
