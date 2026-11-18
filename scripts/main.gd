extends Node3D
## Game flow: title -> level select -> play -> win. All UI is built in code (UiKit).

const BG_SHADER := preload("res://shaders/background.gdshader")
const SPARK_SHADER := preload("res://shaders/spark.gdshader")
const HINTS_PER_LEVEL := 3

var board: Board
var cam: Camera3D
var ui: CanvasLayer
var root: Control
var screen := ""
var level_idx := 0
var level: Dictionary
var world := -1
var hints_left := HINTS_PER_LEVEL
var tut_step := -1
var browse_world := 0

var bg: MeshInstance3D
var bg_mat: ShaderMaterial
var fx: CPUParticles3D
var key_light: DirectionalLight3D
var env: Environment

var lbl_level: Label
var lbl_world: Label
var lbl_moves: Label
var btn_undo: UiKit.IconButton
var btn_hint: UiKit.IconButton
var btn_bottle: UiKit.IconButton
var toast: PanelContainer
var tut_label: Label
var _toast_tw: Tween
var _overlay: Control
var _reset_armed := false
var _log := PackedStringArray()
var _level_token := 0


func _ready() -> void:
	UiKit.init_theme()
	_setup_world()
	ui = CanvasLayer.new()
	add_child(ui)
	get_viewport().size_changed.connect(_on_resize)
	if not (OS.has_feature("web") or OS.has_feature("mobile")):
		get_viewport().msaa_3d = Viewport.MSAA_4X
	if Game.has_arg("--autotest"):
		_autotest()
	elif Game.has_arg("--shots"):
		_shots()
	elif Game.has_arg("--level"):
		start_level(int(Game.arg_value("--level", "1")) - 1)
	else:
		show_title()


func _setup_world() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.02, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.68, 0.85)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	key_light = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-40, -25, 0)
	key_light.light_energy = 0.9
	add_child(key_light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 150, 0)
	fill.light_energy = 0.3
	fill.light_color = Color(0.7, 0.8, 1.0)
	add_child(fill)
	cam = Camera3D.new()
	cam.fov = 30
	cam.far = 400
	add_child(cam)
	cam.current = true
	bg = MeshInstance3D.new()
	bg.mesh = QuadMesh.new()
	bg_mat = ShaderMaterial.new()
	bg_mat.shader = BG_SHADER
	bg.material_override = bg_mat
	bg.position = Vector3(0, 0, -150)
	cam.add_child(bg)
	board = Board.new()
	board.cam = cam
	add_child(board)
	board.poured.connect(_on_poured)
	board.invalid.connect(_on_invalid)
	board.solved.connect(_on_solved)
	board.stuck.connect(_on_stuck)
	board.tapped.connect(_on_tapped)


# ================================================================ world look

func set_world(w: int, instant := false) -> void:
	w = w % Game.WORLDS.size()
	if w == world:
		return
	var info: Dictionary = Game.WORLDS[w]
	var tex: Texture2D = load("res://assets/backgrounds/%s.jpg" % info.id)
	if world < 0 or instant:
		bg_mat.set_shader_parameter("tex_a", tex)
		bg_mat.set_shader_parameter("tex_b", tex)
		bg_mat.set_shader_parameter("mixv", 0.0)
	else:
		bg_mat.set_shader_parameter("tex_b", tex)
		var t := create_tween()
		t.tween_method(func(v): bg_mat.set_shader_parameter("mixv", v), 0.0, 1.0, 0.8)
		t.tween_callback(func():
			bg_mat.set_shader_parameter("tex_a", tex)
			bg_mat.set_shader_parameter("mixv", 0.0))
	world = w
	key_light.light_color = (info.tint as Color).lerp(Color.WHITE, 0.55)
	env.ambient_light_color = (info.tint as Color).lerp(Color(0.8, 0.75, 0.9), 0.6)
	_make_fx(info.fx)


func _make_fx(kind: String) -> void:
	if fx:
		fx.queue_free()
	fx = CPUParticles3D.new()
	var mat := ShaderMaterial.new()
	mat.shader = SPARK_SHADER
	var q := QuadMesh.new()
	q.material = mat
	fx.mesh = q
	fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fx.local_coords = true
	fx.gravity = Vector3.ZERO
	fx.spread = 180.0
	var g := Gradient.new()
	var c := Color.WHITE
	var size := 0.5
	match kind:
		"dust":
			fx.amount = 60; fx.lifetime = 9.0; c = Color(1.0, 0.8, 0.4); size = 0.35
			fx.direction = Vector3(0.2, 1, 0); fx.spread = 30; fx.initial_velocity_min = 0.2; fx.initial_velocity_max = 0.6
		"fireflies":
			fx.amount = 45; fx.lifetime = 7.0; c = Color(0.75, 1.0, 0.35); size = 0.6
			fx.initial_velocity_min = 0.2; fx.initial_velocity_max = 0.8
			fx.angular_velocity_min = -60; fx.angular_velocity_max = 60
		"bubbles":
			fx.amount = 50; fx.lifetime = 8.0; c = Color(0.6, 0.95, 1.0); size = 0.4
			fx.direction = Vector3(0, 1, 0); fx.spread = 12; fx.initial_velocity_min = 0.8; fx.initial_velocity_max = 1.8
		"sparkles":
			fx.amount = 38; fx.lifetime = 4.0; c = Color(1.0, 0.6, 1.0); size = 0.6
			fx.initial_velocity_min = 0.0; fx.initial_velocity_max = 0.2
			mat.set_shader_parameter("star", 1.0)
		"snow":
			fx.amount = 90; fx.lifetime = 10.0; c = Color(0.95, 0.97, 1.0); size = 0.3
			fx.direction = Vector3(0.15, -1, 0); fx.spread = 15; fx.initial_velocity_min = 0.6; fx.initial_velocity_max = 1.2
		_:
			fx.amount = 60; fx.lifetime = 5.0; c = Color(1.0, 0.85, 1.0); size = 0.6
			fx.initial_velocity_min = 0.0; fx.initial_velocity_max = 0.15
			mat.set_shader_parameter("star", 1.0)
	q.size = Vector2(size, size)
	g.set_color(0, Color(c, 0.0))
	g.add_point(0.25, Color(c, 0.9))
	g.add_point(0.6, Color(c, 0.35))
	g.add_point(0.75, Color(c, 0.85))
	g.set_color(g.get_point_count() - 1, Color(c, 0.0))
	fx.color_ramp = g
	fx.scale_amount_min = 0.4
	fx.scale_amount_max = 1.2
	fx.preprocess = fx.lifetime
	cam.add_child(fx)
	_fit_backdrop()


func _fit_backdrop() -> void:
	var vs := get_viewport().get_visible_rect().size
	var aspect := vs.x / maxf(vs.y, 1.0)
	var d := -bg.position.z
	var h := 2.0 * d * tan(deg_to_rad(cam.fov) * 0.5) * 1.04
	var w := h * aspect
	(bg.mesh as QuadMesh).size = Vector2(w, h)
	bg_mat.set_shader_parameter("aspect_fit", Vector2(1.0, h / w) if w > h else Vector2(w / h, 1.0))
	if fx:
		var fd := maxf(cam.global_position.z + 6.0, 20.0)
		fx.position = Vector3(0, 0, -fd)
		var fh := 2.0 * fd * tan(deg_to_rad(cam.fov) * 0.5)
		fx.emission_box_extents = Vector3(fh * aspect * 0.55, fh * 0.55, 3.0)


# ================================================================ camera

func fit_camera(points: Array, top_frac: float, bottom_frac: float, animate := false) -> void:
	if points.is_empty():
		return
	var vs := get_viewport().get_visible_rect().size
	var basis := Basis.from_euler(Vector3(deg_to_rad(-4.0), 0, 0))
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	var target := (lo + hi) * 0.5
	var side := 0.035 * vs.x
	var rect := Rect2(side, vs.y * top_frac, vs.x - 2.0 * side, vs.y * (1.0 - top_frac - bottom_frac))
	var old := cam.global_transform
	var d := 10.0
	for pass_i in 3:
		var a := 2.0
		var b := 200.0
		for it in 26:
			d = (a + b) * 0.5
			cam.global_transform = Transform3D(basis, target + basis.z * d)
			if _points_inside(points, rect):
				b = d
			else:
				a = d
		d = b
		cam.global_transform = Transform3D(basis, target + basis.z * d)
		var sb := _screen_bounds(points)
		var off := rect.get_center() - sb.get_center()
		var wpp := 2.0 * d * tan(deg_to_rad(cam.fov) * 0.5) / vs.y
		target += -basis.x * off.x * wpp + basis.y * off.y * wpp
	var final := Transform3D(basis, target + basis.z * d)
	if animate:
		cam.global_transform = old
		create_tween().tween_property(cam, "global_transform", final, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		cam.global_transform = final
	_fit_backdrop()


func _points_inside(points: Array, rect: Rect2) -> bool:
	for p in points:
		if cam.is_position_behind(p) or not rect.has_point(cam.unproject_position(p)):
			return false
	return true


func _screen_bounds(points: Array) -> Rect2:
	var r := Rect2(cam.unproject_position(points[0]), Vector2.ZERO)
	for p in points:
		r = r.expand(cam.unproject_position(p))
	return r


func _fit_for_screen(animate := false) -> void:
	var vs := get_viewport().get_visible_rect().size
	var portrait := vs.y > vs.x
	if screen == "title":
		fit_camera(board.fit_points(), 0.40 if portrait else 0.30, 0.30 if portrait else 0.40, animate)
	else:
		var top := (0.12 if portrait else 0.15) + safe_top() / vs.y
		var bottom := 0.14 if portrait else 0.19
		if tut_step >= 0:
			bottom += 0.12
		fit_camera(board.fit_points(), top, bottom, animate)


func _on_resize() -> void:
	if board.bottles.is_empty():
		_fit_backdrop()
		return
	board.layout(false)
	_fit_for_screen()


func safe_top() -> float:
	if not OS.has_feature("mobile"):
		return 0.0
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 0.0
	return safe.position.y * get_viewport().get_visible_rect().size.y / win.y


# ================================================================ screens

func _new_root() -> Control:
	if root:
		root.queue_free()
	root = Control.new()
	root.theme = UiKit.theme
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay = null
	toast = null
	tut_label = null
	return root


func _place(c: Control, preset: int, pos := Vector2.ZERO) -> void:
	root.add_child(c)
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	c.position += pos


func show_title() -> void:
	screen = "title"
	board.input_enabled = false
	var w := Game.world_of(maxi(0, int(Game.save.unlocked) - 1))
	set_world(w)
	var demo := {"b": [[1, 1, 1, 1], [7, 7, 7, 7], [3, 3, 3, 3], [10, 10, 10, 10]]}
	if (Game.bottles.has(Game.WORLDS[w].bottle)):
		board.load_level(demo, Game.WORLDS[w].bottle, Game.WORLDS[w].shelf)
	board.input_enabled = false
	_fit_for_screen()
	_new_root()
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	var vsz := get_viewport().get_visible_rect().size
	var t1 := UiKit.label(Game.tr_("title").replace(" ", "
") if vsz.y > vsz.x else Game.tr_("title"), 112 if vsz.y > vsz.x else 96, Color(1, 0.88, 0.45), 16, true)
	t1.add_theme_constant_override("line_spacing", -28)
	var t2 := UiKit.label(Game.tr_("subtitle"), 36, Color(0.9, 0.95, 1.0), 8)
	col.add_child(t1)
	col.add_child(t2)
	_place(col, Control.PRESET_CENTER_TOP, Vector2(0, 40 + safe_top()))
	var tw := t1.create_tween().set_loops()
	tw.tween_property(t1, "position:y", 8.0, 1.6).as_relative().set_trans(Tween.TRANS_SINE)
	tw.tween_property(t1, "position:y", -8.0, 1.6).as_relative().set_trans(Tween.TRANS_SINE)

	var btns := VBoxContainer.new()
	btns.add_theme_constant_override("separation", 22)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	var unlocked := int(Game.save.unlocked)
	var play := UiKit.button(Game.tr_("play") if unlocked <= 1 else "%s  %d" % [Game.tr_("continue"), unlocked], Color(0.2, 0.75, 0.4), Vector2(470, 118), 50)
	play.pressed.connect(func():
		Sfx.start_music()
		start_level(unlocked - 1))
	btns.add_child(play)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	var lv := UiKit.IconButton.new("levels", Color(0.55, 0.3, 0.95), 104)
	lv.pressed.connect(func():
		Sfx.start_music()
		show_levels(Game.world_of(unlocked - 1)))
	row.add_child(lv)
	var st := UiKit.IconButton.new("gear", Color(0.3, 0.5, 0.95), 104)
	st.pressed.connect(func():
		Sfx.start_music()
		show_settings())
	row.add_child(st)
	btns.add_child(row)
	var stars := UiKit.label("★ %d" % Game.total_stars(), 34, Color(1, 0.85, 0.3), 8)
	stars.text = "%s: %d / %d" % [Game.tr_("stars_total"), Game.total_stars(), Game.level_count() * 3]
	btns.add_child(stars)
	_place(btns, Control.PRESET_CENTER_BOTTOM, Vector2(0, -60))
	UiKit.pop_in(play, 0.2)
	UiKit.pop_in(lv, 0.3)
	UiKit.pop_in(st, 0.36)


func show_levels(w: int) -> void:
	screen = "levels"
	browse_world = clampi(w, 0, Game.WORLDS.size() - 1)
	board.clear()
	set_world(browse_world)
	_new_root()
	var vs := get_viewport().get_visible_rect().size
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.01, 0.08, 0.35)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(dim, Control.PRESET_FULL_RECT)

	var back := UiKit.IconButton.new("home", Color(0.55, 0.3, 0.95), 92)
	back.pressed.connect(show_title)
	_place(back, Control.PRESET_TOP_LEFT, Vector2(22, 22 + safe_top()))
	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", -6)
	var wl := UiKit.label(Game.world_name(browse_world), 50, Color(1, 0.9, 0.55), 12, true)
	name_box.add_child(wl)
	var got := 0
	for k in Game.PER_WORLD:
		got += Game.stars_of(browse_world * Game.PER_WORLD + k)
	name_box.add_child(UiKit.label("★".replace("★", "") + "%d / %d" % [got, Game.PER_WORLD * 3], 30, Color(1, 0.85, 0.3), 7))
	root.add_child(name_box)
	name_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	name_box.offset_left = 120
	name_box.offset_right = -120
	name_box.offset_top = 30 + safe_top()
	wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var prev := UiKit.IconButton.new("back", Color(0.3, 0.5, 0.95), 84)
	prev.disabled = browse_world == 0
	prev.pressed.connect(func(): show_levels(browse_world - 1))
	_place(prev, Control.PRESET_TOP_LEFT, Vector2(26, 150 + safe_top()))
	var nxt := UiKit.IconButton.new("next", Color(0.3, 0.5, 0.95), 84)
	nxt.disabled = browse_world >= Game.WORLDS.size() - 1
	nxt.pressed.connect(func(): show_levels(browse_world + 1))
	_place(nxt, Control.PRESET_TOP_RIGHT, Vector2(-26, 150 + safe_top()))

	var cols := 4 if vs.y > vs.x else 5
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	var bsz := clampf((minf(vs.x, 900.0) - 80.0) / cols - 18.0, 100.0, 150.0)
	var unlocked := int(Game.save.unlocked)
	for k in Game.PER_WORLD:
		var idx := browse_world * Game.PER_WORLD + k
		var b := Button.new()
		b.custom_minimum_size = Vector2(bsz, bsz)
		var open := idx < unlocked
		var c := (Game.WORLDS[browse_world].tint as Color)
		UiKit.style_button(b, c.darkened(0.15) if open else Color(0.25, 0.22, 0.32), 30)
		UiKit.juice(b)
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 0)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var num := UiKit.label(str(idx + 1), int(bsz * 0.36), Color.WHITE if open else Color(0.6, 0.55, 0.7), 8)
		v.add_child(num)
		if open:
			v.add_child(UiKit.star_row(Game.stars_of(idx), bsz * 0.22))
		else:
			var lk := UiKit.Lock.new(bsz * 0.26)
			lk.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			v.add_child(lk)
		b.add_child(v)
		if open:
			b.pressed.connect(func(): start_level(idx))
		else:
			b.pressed.connect(func(): show_toast(Game.tr_("locked")))
		if idx == unlocked - 1:
			var tw := b.create_tween().set_loops()
			tw.tween_property(b, "modulate", Color(1.3, 1.3, 1.1), 0.6)
			tw.tween_property(b, "modulate", Color.WHITE, 0.6)
		grid.add_child(b)
	var center := CenterContainer.new()
	center.add_child(grid)
	_place(center, Control.PRESET_FULL_RECT)
	center.offset_top = 250 + safe_top()
	center.offset_bottom = -20
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_make_toast()


func show_settings() -> void:
	var prev := screen
	_reset_armed = false
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.0, 0.06, 0.7)
	_place(shade, Control.PRESET_FULL_RECT)
	var p := UiKit.panel()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	v.add_child(UiKit.label(Game.tr_("settings"), 58, Color(1, 0.88, 0.45), 12, true))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	var snd := UiKit.IconButton.new("sound", Color(0.3, 0.6, 0.95), 110)
	snd.off = not Game.save.sound
	snd.pressed.connect(func():
		Game.save.sound = not Game.save.sound
		snd.off = not Game.save.sound
		snd.queue_redraw()
		Game.write_save())
	var mus := UiKit.IconButton.new("music", Color(0.75, 0.35, 0.95), 110)
	mus.off = not Game.save.music
	mus.pressed.connect(func():
		Game.save.music = not Game.save.music
		mus.off = not Game.save.music
		mus.queue_redraw()
		Sfx.start_music()
		Game.write_save())
	row.add_child(snd)
	row.add_child(mus)
	v.add_child(row)
	var lang := UiKit.button("English" if Game.save.lang == "ru" else "Русский", Color(0.25, 0.6, 0.75), Vector2(400, 96), 40)
	lang.pressed.connect(func():
		Game.save.lang = "en" if Game.save.lang == "ru" else "ru"
		Game.write_save()
		_refresh_screen())
	v.add_child(lang)
	var reset := UiKit.button(Game.tr_("reset"), Color(0.75, 0.25, 0.3), Vector2(400, 84), 32)
	reset.pressed.connect(func():
		if not _reset_armed:
			_reset_armed = true
			reset.text = Game.tr_("reset_q")
			reset.add_theme_font_size_override("font_size", 22)
		else:
			Game.save.unlocked = 1
			Game.save.stars = {}
			Game.save.tutorial = false
			Game.write_save()
			show_title())
	if prev == "title":
		v.add_child(reset)
	var close := UiKit.button(Game.tr_("close"), Color(0.2, 0.7, 0.4), Vector2(400, 100), 44)
	close.pressed.connect(func():
		shade.queue_free()
		p.queue_free())
	v.add_child(close)
	p.add_child(v)
	_place(p, Control.PRESET_CENTER)
	UiKit.pop_in(p)


func _refresh_screen() -> void:
	match screen:
		"title":
			show_title()
		"levels":
			show_levels(browse_world)
		"game":
			_build_hud()
			_update_hud()


func _make_toast() -> void:
	toast = UiKit.pill(30)
	toast.modulate.a = 0.0
	root.add_child(toast)


func show_toast(text: String) -> void:
	if toast == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var l: Label = toast.get_node("L")
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.custom_minimum_size.x = 0
	var full := l.get_minimum_size().x
	var max_w := minf(vs.x - 120.0, 900.0)
	if full > max_w:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = max_w
	toast.reset_size()
	toast.position = Vector2((vs.x - toast.size.x) * 0.5, vs.y - 200 - toast.size.y)
	if _toast_tw:
		_toast_tw.kill()
	_toast_tw = toast.create_tween()
	toast.modulate.a = 0.0
	_toast_tw.tween_property(toast, "modulate:a", 1.0, 0.15)
	_toast_tw.tween_interval(2.2)
	_toast_tw.tween_property(toast, "modulate:a", 0.0, 0.4)


# ================================================================ game

func start_level(idx: int) -> void:
	screen = "game"
	_level_token += 1
	level_idx = maxi(0, idx)
	level = Game.get_level(level_idx)
	var w := Game.world_of(level_idx)
	set_world(w)
	hints_left = HINTS_PER_LEVEL
	board.load_level(level, Game.WORLDS[w].bottle, Game.WORLDS[w].shelf)
	board.input_enabled = true
	tut_step = 0 if level_idx == 0 and not level.get("sol", []).is_empty() else -1
	_fit_for_screen()
	_build_hud()
	_update_hud()
	if tut_step == 0:
		_tutorial()
	elif level.has("h") and level_idx % Game.PER_WORLD == 0 and level_idx < Game.level_count():
		get_tree().create_timer(0.8).timeout.connect(func(): show_toast(Game.tr_("hidden_tip")))


func _build_hud() -> void:
	_new_root()
	var vs := get_viewport().get_visible_rect().size
	var st := safe_top()
	var home := UiKit.IconButton.new("home", Color(0.55, 0.3, 0.95), 92)
	home.pressed.connect(func(): show_levels(Game.world_of(level_idx) if level_idx < Game.level_count() else Game.WORLDS.size() - 1))
	_place(home, Control.PRESET_TOP_LEFT, Vector2(22, 22 + st))
	var gear := UiKit.IconButton.new("gear", Color(0.3, 0.5, 0.95), 92)
	gear.pressed.connect(show_settings)
	_place(gear, Control.PRESET_TOP_RIGHT, Vector2(-22, 22 + st))

	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", -4)
	lbl_level = UiKit.label("", 52, Color(1, 0.9, 0.55), 12, true)
	lbl_world = UiKit.label("", 26, Color(0.92, 0.9, 1.0), 7)
	lbl_moves = UiKit.label("", 28, Color(1, 1, 1), 7)
	head.add_child(lbl_level)
	head.add_child(lbl_world)
	head.add_child(lbl_moves)
	lbl_world.clip_text = true
	root.add_child(head)
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.offset_left = 130
	head.offset_right = -130
	head.offset_top = 14 + st

	var dock := HBoxContainer.new()
	dock.alignment = BoxContainer.ALIGNMENT_CENTER
	var d := 112.0 if vs.y > vs.x else 104.0
	dock.add_theme_constant_override("separation", 26 if vs.x > 600 else 16)
	btn_undo = UiKit.IconButton.new("undo", Color(0.3, 0.55, 0.95), d)
	btn_undo.pressed.connect(_on_undo)
	var btn_restart := UiKit.IconButton.new("restart", Color(0.85, 0.45, 0.2), d)
	btn_restart.pressed.connect(_on_restart)
	btn_hint = UiKit.IconButton.new("hint", Color(0.95, 0.7, 0.15), d)
	btn_hint.pressed.connect(_on_hint)
	btn_bottle = UiKit.IconButton.new("bottle", Color(0.2, 0.7, 0.55), d)
	btn_bottle.pressed.connect(_on_add_bottle)
	for b in [btn_undo, btn_restart, btn_hint, btn_bottle]:
		dock.add_child(b)
	_place(dock, Control.PRESET_CENTER_BOTTOM, Vector2(0, -30))
	_make_toast()
	tut_label = UiKit.label("", 36, Color(1, 1, 0.85), 12)
	tut_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tut_label.custom_minimum_size = Vector2(vs.x - 80, 120)
	root.add_child(tut_label)
	tut_label.position = Vector2(40, vs.y - (300 if vs.y > vs.x else 250))


func _update_hud() -> void:
	if lbl_level == null or not is_instance_valid(lbl_level):
		return
	lbl_level.text = "%s %d" % [Game.tr_("level"), level_idx + 1]
	lbl_world.text = Game.world_name(Game.world_of(level_idx)) if level_idx < Game.level_count() else Game.tr_("endless")
	lbl_moves.text = "%s: %d   •   %s: %d" % [Game.tr_("moves"), board.moves, Game.tr_("best"), int(level.get("par", 0))]
	btn_undo.disabled = board.history.is_empty()
	btn_hint.set_badge(str(hints_left))
	btn_hint.disabled = hints_left <= 0
	btn_bottle.set_badge("+1" if board.extra_added == 0 else "0")
	btn_bottle.disabled = board.extra_added > 0


func _on_poured(_i: int, _j: int) -> void:
	_update_hud()
	if tut_step >= 0:
		tut_step += 1
		_tutorial()


func _on_tapped(i: int) -> void:
	if tut_step >= 0:
		get_tree().process_frame.connect(_tutorial, CONNECT_ONE_SHOT)


func _on_invalid(reason: String) -> void:
	show_toast(Game.tr_(reason))
	if tut_step >= 0:
		get_tree().process_frame.connect(_tutorial, CONNECT_ONE_SHOT)


func _tutorial() -> void:
	if tut_step < 0 or tut_label == null:
		return
	var sol: Array = level.get("sol", [])
	if tut_step >= sol.size() or board.history.size() != tut_step:
		tut_step = -1
		board.point_at(-1)
		tut_label.text = ""
		return
	var m: Array = sol[tut_step]
	if board.selected == int(m[0]):
		board.point_at(int(m[1]))
		tut_label.text = Game.tr_("tut2") if tut_step == 0 else Game.tr_("tut3")
	else:
		board.point_at(int(m[0]))
		tut_label.text = Game.tr_("tut1")


func _on_undo() -> void:
	if not board.undo():
		show_toast(Game.tr_("no_undo"))
		return
	_close_overlay()
	tut_step = -1
	board.point_at(-1)
	if tut_label:
		tut_label.text = ""
	_update_hud()


func _on_restart() -> void:
	Sfx.play("restart", 1.0, -4.0)
	_close_overlay()
	start_level(level_idx)


func _on_hint() -> void:
	if hints_left <= 0:
		show_toast(Game.tr_("no_hint"))
		return
	if board.anims > 0:
		return
	board.request_hint(func(m: Vector2i):
		if m.x < 0:
			show_toast(Game.tr_("hint_none"))
			return
		hints_left -= 1
		Sfx.play("hint", 1.0, -4.0)
		board.show_hint(m)
		_update_hud())


func _on_add_bottle() -> void:
	if board.extra_added > 0:
		show_toast(Game.tr_("bottle_used"))
		return
	if board.anims > 0:
		return
	_close_overlay()
	board.add_bottle()
	_fit_for_screen(true)
	show_toast(Game.tr_("bottle_added"))
	_update_hud()


func stars_for(moves: int) -> int:
	var par := int(level.get("par", moves))
	var s := 1
	if moves <= par:
		s = 3
	elif moves <= par + maxi(2, int(ceil(par * 0.3))):
		s = 2
	if board.extra_added > 0:
		s = mini(s, 2)
	return s


func _on_solved() -> void:
	var stars := stars_for(board.moves)
	var first_world_finish := level_idx % Game.PER_WORLD == Game.PER_WORLD - 1 and level_idx < Game.level_count() and int(Game.save.unlocked) <= level_idx + 1
	Game.record_win(level_idx, stars)
	tut_step = -1
	board.point_at(-1)
	if tut_label:
		tut_label.text = ""
	var token := _level_token
	await get_tree().create_timer(0.35).timeout
	if token != _level_token or screen != "game":
		return
	board.celebrate()
	Sfx.play("win", 1.0, -2.0)
	_confetti()
	await get_tree().create_timer(0.9).timeout
	if screen != "game" or token != _level_token:
		return
	_show_win(stars, first_world_finish)


func _close_overlay() -> void:
	if _overlay and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null


func _show_win(stars: int, world_done: bool) -> void:
	_close_overlay()
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.0, 0.06, 0.55)
	_place(shade, Control.PRESET_FULL_RECT)
	_overlay = shade
	var p := UiKit.panel(Color(0.95, 0.7, 0.2))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := "win%d" % stars
	v.add_child(UiKit.label(Game.tr_(title), 72, Color(1, 0.88, 0.4), 14, true))
	var srow := HBoxContainer.new()
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	srow.add_theme_constant_override("separation", 10)
	var star_nodes: Array = []
	for k in 3:
		var s := UiKit.Star.new(110 if k == 1 else 92, k < stars)
		srow.add_child(s)
		star_nodes.append(s)
	v.add_child(srow)
	v.add_child(UiKit.label("%s: %d   •   %s: %d" % [Game.tr_("moves"), board.moves, Game.tr_("best"), int(level.get("par", 0))], 32, Color.WHITE, 8))
	if world_done:
		v.add_child(UiKit.label(Game.tr_("world_done"), 40, Color(0.6, 1.0, 0.7), 10))
		if level_idx + 1 < Game.level_count():
			v.add_child(UiKit.label("%s: %s" % [Game.tr_("new_world"), Game.world_name(Game.world_of(level_idx + 1))], 30, Color(1, 0.9, 0.7), 8))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	var again := UiKit.IconButton.new("restart", Color(0.85, 0.45, 0.2), 108)
	again.pressed.connect(_on_restart)
	row.add_child(again)
	var nxt := UiKit.button(Game.tr_("next"), Color(0.2, 0.75, 0.4), Vector2(300, 108), 48)
	nxt.pressed.connect(func():
		_close_overlay()
		start_level(level_idx + 1))
	row.add_child(nxt)
	v.add_child(row)
	p.add_child(v)
	shade.add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	UiKit.pop_in(p)
	for k in star_nodes.size():
		var s: Control = star_nodes[k]
		s.scale = Vector2(0.01, 0.01)
		var t := s.create_tween()
		t.tween_interval(0.35 + 0.22 * k)
		t.tween_callback(func():
			s.pivot_offset = s.size * 0.5
			if k < stars:
				Sfx.play("star", 1.0 + 0.12 * k, -3.0))
		t.tween_property(s, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_stuck() -> void:
	if screen != "game":
		return
	_close_overlay()
	var p := UiKit.panel(Color(0.9, 0.35, 0.4))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.add_child(UiKit.label(Game.tr_("stuck"), 52, Color(1, 0.75, 0.7), 12, true))
	v.add_child(UiKit.label(Game.tr_("stuck_sub"), 28, Color.WHITE, 7))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	var u := UiKit.IconButton.new("undo", Color(0.3, 0.55, 0.95), 100)
	u.pressed.connect(_on_undo)
	var r := UiKit.IconButton.new("restart", Color(0.85, 0.45, 0.2), 100)
	r.pressed.connect(_on_restart)
	row.add_child(u)
	row.add_child(r)
	if board.extra_added == 0:
		var b := UiKit.IconButton.new("bottle", Color(0.2, 0.7, 0.55), 100)
		b.pressed.connect(_on_add_bottle)
		row.add_child(b)
	v.add_child(row)
	p.add_child(v)
	_place(p, Control.PRESET_CENTER, Vector2(0, 0))
	_overlay = p
	UiKit.pop_in(p)
	Sfx.play("error", 0.8, -6.0)


func _confetti() -> void:
	var vs := get_viewport().get_visible_rect().size
	for side in [-1, 1]:
		var p := CPUParticles2D.new()
		p.amount = 90
		p.one_shot = true
		p.explosiveness = 0.85
		p.lifetime = 2.6
		p.position = Vector2(vs.x * (0.5 + 0.5 * side), vs.y * 0.75)
		p.direction = Vector2(-side * 0.6, -1)
		p.spread = 25
		p.initial_velocity_min = 900
		p.initial_velocity_max = 1500
		p.gravity = Vector2(0, 1300)
		p.damping_min = 80
		p.damping_max = 160
		p.angular_velocity_min = -720
		p.angular_velocity_max = 720
		p.scale_amount_min = 8
		p.scale_amount_max = 16
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
		g.colors = PackedColorArray([Color("#ff4d6d"), Color("#ffd23f"), Color("#3bceac"), Color("#4cc9f0"), Color("#b5179e"), Color("#ff9e00")])
		p.color_initial_ramp = g
		ui.add_child(p)
		p.emitting = true
		get_tree().create_timer(3.5).timeout.connect(p.queue_free)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		match screen:
			"game":
				show_levels(Game.world_of(level_idx))
			"levels":
				show_title()
			_:
				get_tree().quit()


# ================================================================ autotest

func log_line(s: String) -> void:
	print("AUTOTEST ", s)
	_log.append(s)


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://renders/game")
	DirAccess.make_dir_recursive_absolute(dir)
	var vs := get_viewport().get_visible_rect().size
	var prefix := "land_" if vs.x > vs.y else ""
	get_viewport().get_texture().get_image().save_png(dir + "/" + prefix + name + ".png")


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _idle() -> void:
	var n := 0
	while board.anims > 0 and n < 600:
		await get_tree().process_frame
		n += 1


func _tap_bottle(i: int) -> void:
	var p: Vector2 = get_viewport().get_final_transform() * board.screen_pos_of(i)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = p
	ev.global_position = p
	Input.parse_input_event(ev)
	await get_tree().process_frame
	var ev2 := ev.duplicate()
	ev2.pressed = false
	Input.parse_input_event(ev2)
	await get_tree().process_frame


func _autotest() -> void:
	var fails := 0
	await _wait(0.3)
	# 1. every stored solution solves its level (pure model)
	var bad := 0
	for i in Game.level_count():
		var lv := Game.get_level(i)
		var s: Array = Puzzle.copy(lv.b)
		for m in lv.sol:
			if not Puzzle.can_pour(s, int(m[0]), int(m[1])):
				bad += 1
				break
			Puzzle.apply(s, int(m[0]), int(m[1]))
		if not Puzzle.is_solved(s):
			bad += 1
	for i in [Game.level_count(), Game.level_count() + 7, Game.level_count() + 33]:
		var lv := Game.get_level(i)
		var s: Array = Puzzle.copy(lv.b)
		for m in lv.sol:
			Puzzle.apply(s, int(m[0]), int(m[1]))
		if not Puzzle.is_solved(s):
			bad += 1
	log_line("solutions replay: %d levels, %d bad" % [Game.level_count(), bad])
	fails += int(bad > 0)

	# 2. title + levels screens
	show_title()
	await _wait(1.2)
	await shot("01_title")
	show_levels(0)
	await _wait(0.6)
	await shot("02_levels")
	show_levels(3)
	await _wait(0.9)
	await shot("02b_levels_w4")
	show_settings()
	await _wait(0.6)
	await shot("03_settings")

	# 3. level 1 by taps (tutorial), screenshot mid-pour
	start_level(0)
	await _wait(1.2)
	await shot("04_level1")
	var sol: Array = level.sol
	for k in sol.size():
		await _tap_bottle(int(sol[k][0]))
		await _wait(0.3)
		if k == 0:
			await shot("05_selected")
		await _tap_bottle(int(sol[k][1]))
		if k == 0:
			await _wait(0.55)
			await shot("06_pouring")
		await _idle()
		await _wait(0.1)
	await _wait(1.6)
	await shot("07_win")
	var ok1 := Puzzle.is_solved(board.state) and Game.stars_of(0) > 0
	log_line("level 1 solved by taps: %s, stars %d" % [ok1, Game.stars_of(0)])
	fails += int(not ok1)

	# 4. rejection, undo, hint, extra bottle on level 12
	start_level(11)
	await _wait(1.2)
	var before := JSON.stringify(board.state)
	var bad_pair := Vector2i(-1, -1)
	for i in board.state.size():
		for j in board.state.size():
			if i != j and not (board.state[i] as Array).is_empty() and not Puzzle.is_complete(board.state[i]) and not Puzzle.can_pour(board.state, i, j):
				bad_pair = Vector2i(i, j)
				break
		if bad_pair.x >= 0:
			break
	await _tap_bottle(bad_pair.x)
	await _wait(0.3)
	await _tap_bottle(bad_pair.y)
	await _wait(0.4)
	var rej_ok := JSON.stringify(board.state) == before and board.moves == 0
	log_line("illegal move %s rejected: %s" % [bad_pair, rej_ok])
	fails += int(not rej_ok)
	var m0: Array = level.sol[0]
	await _tap_bottle(int(m0[0]))
	await _wait(0.25)
	await _tap_bottle(int(m0[1]))
	await _idle()
	var moved := board.moves == 1
	_on_undo()
	await _wait(0.2)
	var undo_ok := moved and JSON.stringify(board.state) == before and board.moves == 0
	log_line("move + undo restores state: %s" % undo_ok)
	fails += int(not undo_ok)
	var got := [Vector2i(-2, -2)]
	board.request_hint(func(m): got[0] = m)
	var n := 0
	while got[0].x == -2 and n < 600:
		await get_tree().process_frame
		n += 1
	var hint_ok: bool = got[0].x >= 0 and Puzzle.can_pour(board.state, got[0].x, got[0].y)
	log_line("hint %s legal: %s (%d frames)" % [got[0], hint_ok, n])
	fails += int(not hint_ok)
	board.show_hint(got[0])
	await _wait(0.4)
	await shot("08_hint")
	board.cancel_hint()
	var nb := board.bottles.size()
	_on_add_bottle()
	await _wait(1.0)
	var add_ok: bool = board.bottles.size() == nb + 1 and board.state.size() == nb + 1
	log_line("extra bottle: %s" % add_ok)
	fails += int(not add_ok)
	await shot("09_extra_bottle")

	# 4b. restart while a pour is in flight must not break anything
	start_level(11)
	await _wait(1.0)
	var mm: Array = level.sol[0]
	await _tap_bottle(int(mm[0]))
	await _wait(0.2)
	await _tap_bottle(int(mm[1]))
	await _wait(0.3)
	_on_restart()
	await _wait(1.5)
	var restart_ok: bool = board.moves == 0 and board.anims == 0 and board.bottles.size() == level.b.size()
	log_line("restart mid-pour: %s" % restart_ok)
	fails += int(not restart_ok)

	# 5. stuck detection
	board.state = [[1, 2, 1, 2], [2, 1, 2, 1], [3, 3, 3, 1], [2, 3, 1, 3]]
	board.hidden = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]
	var stuck_ok := Puzzle.useful_moves(board.state).is_empty()
	log_line("stuck detection: %s" % stuck_ok)
	fails += int(not stuck_ok)

	# 6. solve a hidden-layer level by taps (world 4) with the stored solution
	start_level(62)
	await _wait(1.2)
	await shot("10_hidden_layers")
	for m in level.sol:
		var guard := 0
		while ((board.bottles[int(m[0])] as Bottle).busy > 0 or (board.bottles[int(m[1])] as Bottle).busy > 0) and guard < 400:
			await get_tree().process_frame
			guard += 1
		await _tap_bottle(int(m[0]))
		await _wait(0.05)
		await _tap_bottle(int(m[1]))
		await _wait(0.05)
	await _idle()
	await _wait(0.5)
	var ok63 := Puzzle.is_solved(board.state)
	log_line("level 63 (hidden layers) solved by fast taps: %s, moves %d par %d" % [ok63, board.moves, int(level.par)])
	fails += int(not ok63)

	# 7. big boards of every world
	for w in Game.WORLDS.size():
		start_level(w * Game.PER_WORLD + Game.PER_WORLD - 1)
		await _wait(1.3)
		await shot("11_world%d_last" % (w + 1))
	start_level(Game.level_count() + 2)
	await _wait(1.2)
	await shot("12_bonus")

	log_line("DONE fails=%d" % fails)
	var f := FileAccess.open("res://renders/autotest.log", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_log))
	get_tree().quit(1 if fails > 0 else 0)


## Screenshot set for the store / README.
func _shots() -> void:
	start_level(int(Game.arg_value("--shots", "5")) - 1)
	await _wait(1.5)
	await shot("shot_level")
	get_tree().quit()
