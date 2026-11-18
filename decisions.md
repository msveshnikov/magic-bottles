# Decisions (made without asking)

- **3D, not 2D.** Glass bottles are real meshes from Blender; liquids are a shader whose layer boundaries are
  world-horizontal planes. Heights come from per-bottle volume tables (Blender/numpy integrates the cavity at every
  tilt angle), so liquid stays level and volume-correct while a bottle tilts and pours.
- **Rules kept from the web version:** 4 units per bottle, pour onto the same colour or into an empty bottle,
  the whole top run moves as far as it fits, a full single-colour bottle gets a cork.
- **Removed what made the old game unplayable or unfair:**
  - random scramble generation could produce unsolvable boards → every level is a random deal proven solvable by a
    solver (tools/gen_levels.py), with a stored solution the autotest replays;
  - "shuffle" could create a dead board → replaced by **hints** (in-game weighted A*, time-sliced so the web build
    never freezes; 3 per level);
  - undo limited to 5 → unlimited undo;
  - "mystery sacks" with random counters → **hidden layers** ("?"), revealed when they reach the top (worlds 4–6);
  - no progression, difficulty only by a menu → **6 worlds × 20 levels** with a difficulty ramp (2 → 12 colours),
    3-star rating against the solver's par, bonus levels forever after level 120 (permuted copies of late levels).
  - dead ends were silent → "no moves left" panel with undo / restart / extra bottle.
- **+1 bottle** helper kept (once per level) but caps the result at 2 stars.
- Several pours may run at once (model updates instantly, visuals catch up) — only bottles in flight are locked.
- Rows: the board picks 1–3 rows to maximise bottle size for the current screen shape (portrait/landscape/tablet).
- **Android package kept as `com.magicbottles.game`, version 2.0.0 (code 20000), signed with `~/.android/debug.keystore`**
  — the same key as the old Cordova APK, so the new APK installs as an update over the old app.
  The old Cordova release keystore (`water-sort-cordova/signing.keystore`) was copied to
  `~/.android/magicbottles-cordova.keystore` (+ `.txt` with passwords) before the old folders were removed.
- Level generation moved from GDScript to Python (GDScript took >20 min, Python + multiprocessing ~70 s).
- Music: Suno track generated (2 takes); downloading needs the user's last Suno download credit, so a CC0 track is
  shipped until the user approves.
