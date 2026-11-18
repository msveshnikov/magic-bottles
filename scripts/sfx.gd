extends Node
## Sound effects and music. Sources and licences: assets/CREDITS.md.

const A := "res://assets/audio/"
const GROUPS := {
	"select": ["glass_1.ogg"],
	"clink": ["glass_2.ogg", "glass_3.ogg", "glass_4.ogg", "glass_5.ogg", "glass_6.ogg"],
	"deselect": ["drop_1.ogg", "drop_2.ogg"],
	"pour": ["pour_1.ogg", "pour_2.ogg"],
	"bubble": ["bubble_1.ogg", "bubble_2.ogg", "bubble_3.ogg"],
	"splash": ["splash_1.ogg", "splash_2.ogg"],
	"cork": ["cork_1.ogg", "cork_2.ogg", "cork_3.ogg"],
	"uncork": ["uncork_1.ogg", "uncork_2.ogg"],
	"shake": ["shake_1.ogg", "shake_2.ogg", "shake_3.ogg"],
	"error": ["error.ogg", "error2.ogg"],
	"click": ["click.ogg"],
	"undo": ["undo.ogg"],
	"hint": ["hint.ogg"],
	"complete": ["complete.ogg"],
	"toggle": ["toggle.ogg"],
	"restart": ["restart.ogg"],
	"pop": ["pop.ogg"],
	"powerup": ["powerup.ogg"],
	"star": ["star.ogg"],
	"sparkle": ["sparkle.ogg"],
	"win": ["win_vibraphone.ogg", "win_pizzicato.ogg", "win_grandpiano.ogg", "win_fantasia.ogg", "win_steeldrums.ogg"],
}

var streams := {}
var players: Array[AudioStreamPlayer] = []
var music: AudioStreamPlayer
var _next := 0
var _music_started := false
var _pours := {}   # id -> player


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for g in GROUPS:
		var arr: Array = []
		for f in GROUPS[g]:
			var s = load(A + f)
			if s:
				arr.append(s)
		streams[g] = arr
	for i in 14:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	music = AudioStreamPlayer.new()
	add_child(music)
	var m = null
	for f in ["music.mp3", "music.ogg"]:
		if ResourceLoader.exists(A + f):
			m = load(A + f)
			break
	if m:
		m.loop = true
		music.stream = m
	music.volume_db = -13.0


func _free_player() -> AudioStreamPlayer:
	for i in players.size():
		var c := players[(_next + i) % players.size()]
		if not c.playing:
			_next += 1
			return c
	_next += 1
	return players[_next % players.size()]


func play(name: String, pitch := 1.0, vol := 0.0) -> AudioStreamPlayer:
	if not Game.save.sound:
		return null
	var arr: Array = streams.get(name, [])
	if arr.is_empty():
		return null
	var p := _free_player()
	p.stream = arr.pick_random()
	p.pitch_scale = clampf(pitch, 0.3, 4.0)
	p.volume_db = vol
	p.play()
	return p


## A pouring sound that lasts until stop_pour(id); pitch rises as the target fills.
func start_pour(id: int, pitch := 1.0) -> void:
	var p := play("pour", pitch, -4.0)
	if p:
		_pours[id] = p


func pour_pitch(id: int, pitch: float) -> void:
	var p: AudioStreamPlayer = _pours.get(id)
	if p and p.playing:
		p.pitch_scale = pitch


func stop_pour(id: int) -> void:
	var p: AudioStreamPlayer = _pours.get(id)
	_pours.erase(id)
	if p and p.playing:
		var t := create_tween()
		t.tween_property(p, "volume_db", -40.0, 0.18)
		t.tween_callback(p.stop)


func stop_all_pours() -> void:
	for id in _pours.keys():
		stop_pour(id)


## Browsers block audio until the first user gesture: call this from a button press.
func start_music() -> void:
	_music_started = true
	update_music()


func update_music() -> void:
	if music.stream == null:
		return
	if Game.save.music and _music_started:
		if not music.playing:
			music.play()
	else:
		music.stop()
