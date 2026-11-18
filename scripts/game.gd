extends Node
## Global state: palette, worlds, levels, save file, settings, translations, command-line flags.

const SAVE_PATH := "user://save.json"
const LEVELS_PATH := "res://assets/levels/levels.json"
const PER_WORLD := 20

## Liquid colours, picked to stay distinct under the unshaded liquid shader.
const PALETTE := [
	Color(0, 0, 0),            # 0 unused
	Color("#ee2a3c"),          # 1 red
	Color("#ff8c1a"),          # 2 orange
	Color("#ffe033"),          # 3 yellow
	Color("#a2ef3c"),          # 4 lime
	Color("#14a650"),          # 5 green
	Color("#1fe0d0"),          # 6 turquoise
	Color("#4aa8ff"),          # 7 sky blue
	Color("#2a3fe6"),          # 8 royal blue
	Color("#9440f0"),          # 9 violet
	Color("#ff63cb"),          # 10 pink
	Color("#8f4d1f"),          # 11 brown
	Color("#f2f2fa"),          # 12 pearl white
]

const WORLDS := [
	{"id": "workshop", "bottle": "flask", "en": "Alchemist's Workshop", "ru": "Мастерская алхимика",
		"tint": Color(1.0, 0.72, 0.38), "fx": "dust", "shelf": Color(1, 0.85, 0.7)},
	{"id": "forest", "bottle": "tube", "en": "Enchanted Forest", "ru": "Зачарованный лес",
		"tint": Color(0.55, 1.0, 0.6), "fx": "fireflies", "shelf": Color(0.8, 1, 0.8)},
	{"id": "ocean", "bottle": "jar", "en": "Sunken Palace", "ru": "Подводный дворец",
		"tint": Color(0.4, 0.9, 1.0), "fx": "bubbles", "shelf": Color(0.75, 0.95, 1)},
	{"id": "crystal", "bottle": "flask", "en": "Crystal Caves", "ru": "Хрустальные пещеры",
		"tint": Color(0.85, 0.55, 1.0), "fx": "sparkles", "shelf": Color(0.9, 0.8, 1)},
	{"id": "aurora", "bottle": "tube", "en": "Northern Lights", "ru": "Северное сияние",
		"tint": Color(0.5, 1.0, 0.85), "fx": "snow", "shelf": Color(0.85, 0.95, 1)},
	{"id": "cosmos", "bottle": "jar", "en": "Star Nebula", "ru": "Звёздная туманность",
		"tint": Color(1.0, 0.5, 0.9), "fx": "stars", "shelf": Color(0.95, 0.8, 1)},
]

var levels: Array = []
var bottles: Dictionary = {}   # bottle type -> profile + volume tables (bottles.json)
var save := {
	"unlocked": 1,      # highest playable level (1-based)
	"stars": {},        # "idx" -> stars
	"lang": "",
	"sound": true,
	"music": true,
	"tutorial": false,
}
var args := PackedStringArray()


func _ready() -> void:
	args = OS.get_cmdline_user_args()
	var f := FileAccess.open(LEVELS_PATH, FileAccess.READ)
	if f:
		levels = JSON.parse_string(f.get_as_text())
	var fb := FileAccess.open("res://assets/models/bottles.json", FileAccess.READ)
	if fb:
		bottles = JSON.parse_string(fb.get_as_text())
	load_save()
	if save.lang == "":
		save.lang = "ru" if OS.get_locale_language() in ["ru", "uk", "be", "kk"] else "en"
	if has_arg("--fresh"):
		save.unlocked = 1
		save.stars = {}
		save.tutorial = false
	if has_arg("--lang"):
		save.lang = arg_value("--lang", "en")


func has_arg(a: String) -> bool:
	return a in args


func arg_value(a: String, def := "") -> String:
	var i := args.find(a)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return def


func load_save() -> void:
	if has_arg("--autotest") or has_arg("--fresh"):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		for k in d:
			save[k] = d[k]


func write_save() -> void:
	if has_arg("--autotest"):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save))


func level_count() -> int:
	return levels.size()


func world_of(idx: int) -> int:
	return clampi(idx / PER_WORLD, 0, WORLDS.size() - 1) if idx < levels.size() else (idx / PER_WORLD) % WORLDS.size()


## Level data. Past the campaign, levels from the last worlds come back with colours and
## bottle order permuted (same structure, so still solvable), forever.
func get_level(idx: int) -> Dictionary:
	if idx < levels.size():
		return levels[idx]
	var rng := RandomNumberGenerator.new()
	rng.seed = idx * 7919 + 17
	var src_i := rng.randi_range(levels.size() - 3 * PER_WORLD, levels.size() - 1)
	var src: Dictionary = levels[src_i]
	var cols := range(1, PALETTE.size())
	for i in range(cols.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = cols[i]; cols[i] = cols[j]; cols[j] = t
	var used := {}
	for b in src.b:
		for u in b:
			used[int(u)] = true
	var remap := {}
	var k := 0
	for u in used:
		remap[u] = cols[k]
		k += 1
	var order := range(src.b.size())
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = order[i]; order[i] = order[j]; order[j] = t
	var nb: Array = []
	var nh: Array = []
	for o in order:
		var b: Array = []
		for u in src.b[o]:
			b.append(remap[int(u)])
		nb.append(b)
		if src.has("h") and src.h is Array:
			nh.append(src.h[o])
	var inv := {}
	for n in order.size():
		inv[order[n]] = n
	var sol: Array = []
	for m in src.get("sol", []):
		sol.append([inv[int(m[0])], inv[int(m[1])]])
	var d := {"b": nb, "par": src.par, "sol": sol}
	if not nh.is_empty():
		d["h"] = nh
	return d


func stars_of(idx: int) -> int:
	return int(save.stars.get(str(idx), 0))


func total_stars() -> int:
	var n := 0
	for k in save.stars:
		n += int(save.stars[k])
	return n


func record_win(idx: int, stars: int) -> void:
	if stars > stars_of(idx):
		save.stars[str(idx)] = stars
	save.unlocked = maxi(int(save.unlocked), idx + 2)
	write_save()


func world_name(w: int) -> String:
	return WORLDS[w % WORLDS.size()][save.lang if save.lang in ["en", "ru"] else "en"]


# ================================================================== text

const TEXT := {
	"title": ["Magic Bottles", "Волшебные бутылочки"],
	"subtitle": ["Sort the potions!", "Разлей зелья по цветам!"],
	"play": ["Play", "Играть"],
	"continue": ["Continue", "Продолжить"],
	"levels": ["Levels", "Уровни"],
	"settings": ["Settings", "Настройки"],
	"level": ["Level", "Уровень"],
	"moves": ["Moves", "Ходы"],
	"best": ["Target", "Цель"],
	"undo": ["Undo", "Отмена"],
	"hint": ["Hint", "Подсказка"],
	"bottle": ["Bottle", "Колба"],
	"restart": ["Restart", "Заново"],
	"win1": ["Brilliant!", "Великолепно!"],
	"win2": ["Masterful!", "Мастерски!"],
	"win3": ["Perfect!", "Идеально!"],
	"next": ["Next", "Дальше"],
	"replay": ["Replay", "Ещё раз"],
	"stuck": ["No moves left", "Ходов больше нет"],
	"stuck_sub": ["Undo a move or start over", "Отмените ход или начните заново"],
	"no_undo": ["Nothing to undo", "Нечего отменять"],
	"no_hint": ["No hints left on this level", "Подсказки на этом уровне закончились"],
	"hint_none": ["No way out from here — undo a few moves", "Отсюда не выбраться — отмените несколько ходов"],
	"bottle_used": ["Only one extra bottle per level", "Только одна дополнительная колба за уровень"],
	"bottle_added": ["+1 empty bottle (max 2 stars)", "+1 пустая колба (максимум 2 звезды)"],
	"tut1": ["Tap a bottle to pick it up", "Коснитесь бутылочки, чтобы взять её"],
	"tut2": ["Now tap where to pour", "Теперь коснитесь, куда налить"],
	"tut3": ["Same colour on top, or an empty bottle!", "Наливать можно на тот же цвет или в пустую!"],
	"rule_bad": ["Only onto the same colour or into an empty bottle", "Только на тот же цвет или в пустую колбу"],
	"rule_full": ["That bottle is full", "Эта колба уже полна"],
	"sound": ["Sound", "Звуки"],
	"music": ["Music", "Музыка"],
	"language": ["Language", "Язык"],
	"close": ["Close", "Закрыть"],
	"locked": ["Win the previous level first", "Сначала пройдите предыдущий уровень"],
	"world_done": ["World complete!", "Мир пройден!"],
	"new_world": ["New world unlocked", "Открыт новый мир"],
	"endless": ["Bonus levels", "Бонусные уровни"],
	"hidden_tip": ["Hidden layers show up when they reach the top", "Скрытые слои откроются, когда окажутся сверху"],
	"stars_total": ["Stars", "Звёзды"],
	"reset": ["Reset progress", "Сбросить прогресс"],
	"reset_q": ["Tap again to erase all progress", "Нажмите ещё раз, чтобы стереть прогресс"],
}


func tr_(key: String) -> String:
	var row: Array = TEXT.get(key, [key, key])
	return row[1] if save.lang == "ru" else row[0]
