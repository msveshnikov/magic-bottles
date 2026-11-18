class_name Board
extends Node3D
## The 3D play field: bottles on shelves, tap handling, pour animation, effects, undo, hints.
## The model (state/hidden) changes instantly; the visuals catch up with animations, so several
## pours can run at once as long as they don't share a bottle.

signal poured(i: int, j: int)
signal invalid(reason: String)
signal completed(i: int)
signal solved
signal stuck
signal tapped(i: int)

const PITCH_X := 1.24
const ROW_GAP := 3.6
const LIFT := 0.5
const STREAM_SHADER := preload("res://shaders/stream.gdshader")
const SPARK_SHADER := preload("res://shaders/spark.gdshader")
const DROP_SHADER := preload("res://shaders/drop.gdshader")

var cam: Camera3D
var state: Array = []
var hidden: Array = []
var bottles: Array = []        # Bottle
var kind := "flask"
var selected := -1
var history: Array = []
var moves := 0
var input_enabled := true
var anims := 0
var extra_added := 0
var shelf_tint := Color.WHITE
var _rows: Array = []
var _shelves: Array = []
var _shelf_scene: PackedScene
var _arrow: Node3D
var _arrow_target := -1
var _hint_solver = null
var _hint_cb: Callable
var _hint_idx := -1
var _hint_t0 := 0
var _pour_id := 0
var _spark_mat: ShaderMaterial
var _star_mat: ShaderMaterial
var _drop_mat: ShaderMaterial
var _done_flag := false
var portrait := true


func _ready() -> void:
	_shelf_scene = load("res://assets/models/shelf.glb")
	_spark_mat = ShaderMaterial.new()
	_spark_mat.shader = SPARK_SHADER
	_star_mat = ShaderMaterial.new()
	_star_mat.shader = SPARK_SHADER
	_star_mat.set_shader_parameter("star", 1.0)
	_drop_mat = ShaderMaterial.new()
	_drop_mat.shader = DROP_SHADER
	_make_arrow()


# =============================================================== level setup

func load_level(level: Dictionary, bottle_kind: String, tint: Color) -> void:
	clear()
	kind = bottle_kind
	shelf_tint = tint
	for b in level.b:
		state.append((b as Array).map(func(u): return int(u)))
	var hs: Array = level.get("h", [])
	for i in state.size():
		var h: Array = []
		for k in (state[i] as Array).size():
			h.append(int(hs[i][k]) if i < hs.size() and k < (hs[i] as Array).size() else 0)
		hidden.append(h)
	for i in state.size():
		_spawn_bottle(i)
	layout(false)
	for i in bottles.size():
		var b: Bottle = bottles[i]
		var to := b.position
		b.position = to + Vector3(0, 6.0 + i * 0.25, 0)
		var t := b.create_tween()
		t.tween_interval(0.04 * i)
		t.tween_property(b, "position", to, 0.55).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		t.tween_callback(func(): b.kick(1.6); Sfx.play("clink", randf_range(0.9, 1.2), -10.0))


func clear() -> void:
	Sfx.stop_all_pours()
	for c in get_children():
		if c is CPUParticles3D or (c is MeshInstance3D and c.material_override is ShaderMaterial and (c.material_override as ShaderMaterial).shader == STREAM_SHADER):
			c.queue_free()
	for b in bottles:
		b.queue_free()
	for s in _shelves:
		s.queue_free()
	bottles.clear()
	_shelves.clear()
	state.clear()
	hidden.clear()
	history.clear()
	selected = -1
	moves = 0
	anims = 0
	extra_added = 0
	_done_flag = false
	input_enabled = true
	cancel_hint()


func _spawn_bottle(i: int) -> Bottle:
	var b := Bottle.new()
	b.index = i
	add_child(b)
	b.setup(kind, state[i], hidden[i])
	if Puzzle.is_complete(state[i]):
		b.corked = true
		b.cork.visible = true
	bottles.append(b)
	return b


func _row_split(n: int) -> Array:
	var vs := get_viewport().get_visible_rect().size
	portrait = vs.y > vs.x * 1.05
	# pick the row count that gives the biggest bottles on this screen shape
	var avail := Vector2(vs.x * 0.93, vs.y * (0.72 if portrait else 0.64))
	var best_r := 1
	var best_s := 0.0
	for r in range(1, 4):
		var per := int(ceil(n / float(r)))
		if r > 1 and per < 3:
			break
		var w := per * PITCH_X + 0.4
		var h := (r - 1) * ROW_GAP + 3.4
		var sc := minf(avail.x / w, avail.y / h)
		if sc > best_s * 1.04:
			best_s = sc
			best_r = r
	var rows: Array = []
	var per_row := int(ceil(n / float(best_r)))
	var start := 0
	for r in best_r:
		var cnt := mini(per_row, n - start)
		if r == best_r - 1:
			cnt = n - start
		rows.append(range(start, start + cnt))
		start += cnt
	return rows


func layout(animate := true) -> void:
	_rows = _row_split(bottles.size())
	var nrows := _rows.size()
	for r in nrows:
		var row: Array = _rows[r]
		var m := row.size()
		var y := (nrows - 1 - r) * ROW_GAP
		for k in m:
			var b: Bottle = bottles[row[k]]
			b.home = Vector3((k - (m - 1) * 0.5) * PITCH_X, y, 0)
			var dest := b.home + (Vector3(0, LIFT, 0) if b.selected else Vector3.ZERO)
			if b.busy > 0:
				continue
			if animate:
				b.create_tween().tween_property(b, "position", dest, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			else:
				b.position = dest
	_build_shelves()


func _build_shelves() -> void:
	for s in _shelves:
		s.queue_free()
	_shelves.clear()
	var max_m := 0
	for row in _rows:
		max_m = maxi(max_m, (row as Array).size())
	for r in _rows.size():
		var y := (_rows.size() - 1 - r) * ROW_GAP
		var w := max_m * PITCH_X + 0.3
		var inst: Node3D = _shelf_scene.instantiate()
		var root := Node3D.new()
		add_child(root)
		root.position = Vector3(0, y, 0)
		for nm in ["ShelfMid", "ShelfCapL", "ShelfCapR"]:
			var src := inst.find_child(nm, true, false) as MeshInstance3D
			if src == null:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = src.mesh
			root.add_child(mi)
			if nm == "ShelfMid":
				mi.scale = Vector3(w, 1, 1)
			else:
				mi.position.x = (w * 0.5 + 0.02) * (-1.0 if nm == "ShelfCapL" else 1.0)
			for si in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(si)
				if m is StandardMaterial3D:
					var mm: StandardMaterial3D = m.duplicate()
					mm.albedo_color = mm.albedo_color * shelf_tint
					mi.set_surface_override_material(si, mm)
		inst.free()
		_shelves.append(root)


## Points that must stay on screen (for the camera fit).
func fit_points() -> Array:
	var pts: Array = []
	for b in bottles:
		var r := float(b.prof.body_r) + 0.12
		var top := float(b.prof.y_top) + 0.3 + LIFT
		if _rows.size() > 0 and b.index in _rows[0]:
			top += 0.7   # room for the hint arrow above the top row
		for p in [Vector3(-r, -0.2, 0), Vector3(r, -0.2, 0), Vector3(-r, top, 0), Vector3(r, top, 0)]:
			pts.append(b.home + p)
	return pts


# =============================================================== input

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var i := pick(e.position)
		if i >= 0:
			get_viewport().set_input_as_handled()
			tap(i)
		elif selected >= 0 and input_enabled:
			_deselect()


func screen_rect_of(i: int) -> Rect2:
	var b: Bottle = bottles[i]
	var r := float(b.prof.body_r) + 0.14
	var top := float(b.prof.y_top) + 0.3 + (LIFT if b.selected else 0.0)
	var rect := Rect2()
	var first := true
	for p in [Vector3(-r, -0.15, 0), Vector3(r, -0.15, 0), Vector3(-r, top, 0), Vector3(r, top, 0)]:
		var sp := cam.unproject_position(to_global(b.home + p))
		if first:
			rect = Rect2(sp, Vector2.ZERO)
			first = false
		else:
			rect = rect.expand(sp)
	return rect


func screen_pos_of(i: int) -> Vector2:
	return screen_rect_of(i).get_center()


func pick(pos: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in bottles.size():
		var rect := screen_rect_of(i)
		var d := rect.get_center().distance_to(pos)
		if rect.grow(6).has_point(pos) and d < best_d:
			best = i
			best_d = d
	return best


func tap(i: int) -> void:
	if not input_enabled or i < 0 or i >= bottles.size():
		return
	tapped.emit(i)
	var b: Bottle = bottles[i]
	if b.busy > 0:
		return
	cancel_hint(false)
	if selected < 0:
		var s: Array = state[i]
		if s.is_empty():
			_shake(i)
			Sfx.play("shake", 1.2, -6.0)
			return
		if Puzzle.is_complete(s):
			_hop(i)
			Sfx.play("clink", randf_range(1.0, 1.3), -4.0)
			return
		_select(i)
	elif selected == i:
		_deselect()
	else:
		var from := selected
		if Puzzle.can_pour(state, from, i):
			_pour(from, i)
		else:
			var reason := "rule_full" if (state[i] as Array).size() >= Puzzle.CAP else "rule_bad"
			Sfx.play("error", 1.0, -6.0)
			_shake(i)
			_deselect()
			invalid.emit(reason)


func _select(i: int) -> void:
	selected = i
	var b: Bottle = bottles[i]
	b.set_selected(true)
	b.create_tween().tween_property(b, "position", b.home + Vector3(0, LIFT, 0), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("select", randf_range(0.95, 1.1), -3.0)


func _deselect() -> void:
	if selected < 0:
		return
	var b: Bottle = bottles[selected]
	selected = -1
	b.set_selected(false)
	if b.busy == 0:
		var t := b.create_tween()
		t.tween_property(b, "position", b.home, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_callback(func(): b.kick(1.2))
	Sfx.play("deselect", 1.0, -8.0)


func _shake(i: int) -> void:
	var b: Bottle = bottles[i]
	if b.busy > 0:
		return
	var t := b.create_tween()
	for k in 4:
		var a := deg_to_rad(7.0 if k % 2 == 0 else -7.0) * (1.0 - k * 0.2)
		t.tween_property(b, "rotation:z", a, 0.05)
	t.tween_property(b, "rotation:z", 0.0, 0.06)
	b.kick(3.0)


func _hop(i: int) -> void:
	var b: Bottle = bottles[i]
	if b.busy > 0:
		return
	var t := b.create_tween()
	t.tween_property(b, "position", b.home + Vector3(0, 0.25, 0), 0.12).set_ease(Tween.EASE_OUT)
	t.tween_property(b, "position", b.home, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


# =============================================================== moves

func _snapshot() -> Dictionary:
	return {"s": Puzzle.copy(state), "h": Puzzle.copy(hidden)}


func _pour(i: int, j: int) -> void:
	var amount := Puzzle.pour_amount(state, i, j)
	var color: int = state[i][-1]
	history.append(_snapshot())
	moves += 1
	for k in amount:
		state[j].append(state[i].pop_back())
		hidden[i].pop_back()
		hidden[j].append(0)
	var reveal := false
	if not (hidden[i] as Array).is_empty() and hidden[i][-1] == 1:
		hidden[i][-1] = 0
		reveal = true
	selected = -1
	poured.emit(i, j)
	_animate_pour(i, j, color, amount, reveal)


func _rot(angle: float, dir: int) -> Basis:
	return Basis(Vector3(0, 0, 1), -dir * deg_to_rad(angle))


func _animate_pour(i: int, j: int, color: int, amount: int, reveal: bool) -> void:
	anims += 1
	_pour_id += 1
	var pid := _pour_id
	var src: Bottle = bottles[i]
	var tgt: Bottle = bottles[j]
	src.busy += 1
	tgt.busy += 1
	src.set_selected(false)
	var dir := 1
	if tgt.home.x < src.home.x - 0.01:
		dir = -1
	elif absf(tgt.home.x - src.home.x) <= 0.01:
		dir = 1 if tgt.home.x > 0.0 else -1
	src.tilt_dir = dir
	var lip := Vector3(dir * float(src.prof.neck_r), float(src.prof.y_top), 0)
	var units0 := src.total_units()
	var a_start := src.pour_angle(units0) - 4.0
	var a_end := src.pour_angle(units0 - amount) + 2.0
	var mouth := tgt.home + Vector3(0, float(tgt.prof.y_top), 0)
	var P := mouth + Vector3(-dir * 0.06, 0.38, 0.6)
	var start := src.position
	var src_segs0: Array = _dup_segs(src.segs)
	var tgt_segs0: Array = _dup_segs(tgt.segs)
	var col: Color = Game.PALETTE[color]

	# A: fly over and tip up to the brink
	var ta := src.create_tween()
	ta.tween_method(func(s: float):
		var ang := a_start * s
		src.set_tilt(ang, dir)
		src.position = start.lerp(P - _rot(ang, dir) * lip, s)
		src.refresh(), 0.0, 1.0, 0.34).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await ta.finished
	if not is_instance_valid(src) or not is_instance_valid(tgt):
		anims -= 1
		return

	# B: pour
	var stream := _make_stream(col)
	var splash := _make_splash(col)
	Sfx.start_pour(pid, 0.9 + 0.08 * tgt.total_units())
	var dur := 0.22 + 0.17 * amount
	var tb := src.create_tween()
	tb.tween_method(func(q: float):
		var units := units0 - amount * q
		var ang := lerpf(a_start, a_end, q) if q < 0.15 else src.pour_angle(units) + 2.0
		ang = maxf(ang, lerpf(a_start, a_end, q))
		src.set_tilt(ang, dir)
		src.position = P - _rot(ang, dir) * lip
		src.segs = _drain(src_segs0, amount * q)
		src.refresh()
		tgt.segs = _fill(tgt_segs0, color, amount * clampf(q * 1.08 - 0.04, 0.0, 1.0))
		tgt.refresh()
		var top_y := tgt.position.y + tgt.surf_h(0.0, tgt.total_units() * float(tgt.prof.unit))
		var lip_w := to_global(P)
		var bot := Vector3(lip_w.x, to_global(Vector3(0, top_y, 0)).y, lip_w.z)
		var thick := clampf(minf(q * 6.0, (1.0 - q) * 5.0 + 0.25), 0.15, 1.0)
		_place_stream(stream, lip_w, bot, thick)
		splash.global_position = bot
		Sfx.pour_pitch(pid, 0.9 + 0.1 * tgt.total_units()), 0.0, 1.0, dur)
	await tb.finished
	Sfx.stop_pour(pid)
	if is_instance_valid(stream):
		var ts := stream.create_tween()
		ts.tween_property(stream, "scale:x", 0.01, 0.12)
		ts.parallel().tween_property(stream, "scale:z", 0.01, 0.12)
		ts.tween_callback(stream.queue_free)
	if is_instance_valid(splash):
		splash.emitting = false
		_free_later(splash, 1.0)
	if not is_instance_valid(src) or not is_instance_valid(tgt):
		anims -= 1
		return
	tgt.kick(-dir * 2.0)
	Sfx.play("bubble", randf_range(0.9, 1.2), -8.0)

	# C: back home
	tgt.busy -= 1
	tgt.set_units(state[j], hidden[j])
	if Puzzle.is_complete(state[j]):
		_complete(j)
	var tc := src.create_tween()
	var p_end := src.position
	tc.tween_method(func(s: float):
		var ang := a_end * (1.0 - s)
		src.set_tilt(ang, dir)
		src.position = p_end.lerp(src.home, s)
		src.refresh(), 0.0, 1.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tc.finished
	if not is_instance_valid(src):
		anims -= 1
		return
	src.set_tilt(0.0, dir)
	src.position = src.home
	src.busy -= 1
	src.set_units(state[i], hidden[i])
	src.kick(dir * 2.5)
	Sfx.play("clink", randf_range(0.9, 1.15), -12.0)
	if reveal:
		src.flash(0.7)
		_puff(src.global_position + Vector3(0, src.surf_h(0.0, src.total_units() * float(src.prof.unit)), 0.3), Color(0.8, 0.7, 1.0))
		Sfx.play("pop", 1.2, -6.0)
	anims -= 1
	_check_end()


func _dup_segs(a: Array) -> Array:
	var o: Array = []
	for s in a:
		o.append((s as Dictionary).duplicate())
	return o


func _drain(segs0: Array, amount: float) -> Array:
	var o := _dup_segs(segs0)
	var left := amount
	while left > 0.0001 and not o.is_empty():
		var t: Dictionary = o[-1]
		var take := minf(left, t.v)
		t.v -= take
		left -= take
		if t.v <= 0.0001:
			o.pop_back()
	return o


func _fill(segs0: Array, color: int, amount: float) -> Array:
	var o := _dup_segs(segs0)
	if amount <= 0.0:
		return o
	if not o.is_empty() and o[-1].c == color and not o[-1].hid:
		o[-1].v += amount
	else:
		o.append({"c": color, "v": amount, "hid": false})
	return o


func _check_end() -> void:
	if anims > 0 or _done_flag:
		return
	if Puzzle.is_solved(state):
		_done_flag = true
		input_enabled = false
		solved.emit()
	elif Puzzle.useful_moves(state).is_empty():
		stuck.emit()


func _complete(j: int) -> void:
	var b: Bottle = bottles[j]
	b.corked = true
	b.cork.visible = true
	b.cork.position = Vector3(0, 1.6, 0)
	b.cork.scale = Vector3.ONE * 1.3
	var t := b.cork.create_tween()
	t.tween_property(b.cork, "position", Vector3.ZERO, 0.42).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(b.cork, "scale", Vector3.ONE, 0.3)
	b.celebrate()
	var done := 0
	for s in state:
		if Puzzle.is_complete(s):
			done += 1
	Sfx.play("cork", 1.0, -2.0)
	var tsnd := b.create_tween()
	tsnd.tween_interval(0.18)
	tsnd.tween_callback(func(): Sfx.play("complete", 0.9 + 0.06 * done, -4.0))
	_burst(b.global_position + Vector3(0, float(b.prof.y_top) + 0.1, 0.2), Game.PALETTE[state[j][0]])
	completed.emit(j)


# =============================================================== effects

func _free_later(n: Node, t: float) -> void:
	var tw := n.create_tween()
	tw.tween_interval(t)
	tw.tween_callback(n.queue_free)


func _make_stream(col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.043
	cyl.height = 1.0
	cyl.radial_segments = 12
	cyl.rings = 1
	m.mesh = cyl
	var mat := ShaderMaterial.new()
	mat.shader = STREAM_SHADER
	mat.set_shader_parameter("color", col)
	m.material_override = mat
	add_child(m)
	m.scale = Vector3(0.01, 0.01, 0.01)
	return m


func _place_stream(m: MeshInstance3D, a: Vector3, b: Vector3, thick: float) -> void:
	var len := maxf(a.y - b.y, 0.02)
	m.global_position = Vector3(a.x, (a.y + b.y) * 0.5, a.z)
	m.scale = Vector3(thick, len, thick)


func _particles(amount: int, mat: Material, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	p.mesh = q
	p.local_coords = false
	add_child(p)
	return p


func _make_splash(col: Color) -> CPUParticles3D:
	var p := _particles(26, _drop_mat, 0.085)
	p.lifetime = 0.42
	p.direction = Vector3(0, 1, 0)
	p.spread = 55.0
	p.initial_velocity_min = 0.9
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, -11, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.1
	var g := Gradient.new()
	g.set_color(0, col.lightened(0.15))
	g.set_color(1, Color(col, 0.0))
	p.color_ramp = g
	p.emitting = true
	return p


func _burst(pos: Vector3, col: Color) -> void:
	var p := _particles(40, _star_mat, 0.32)
	p.global_position = pos
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 1.1
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.6
	p.gravity = Vector3(0, -2.5, 0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.scale_amount_min = 0.35
	p.scale_amount_max = 1.0
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.95, 0.7, 1))
	g.add_point(0.35, col.lightened(0.3))
	g.set_color(g.get_point_count() - 1, Color(col, 0))
	p.color_ramp = g
	p.emitting = true
	_free_later(p, 2.0)


func _puff(pos: Vector3, col: Color) -> void:
	var p := _particles(18, _spark_mat, 0.35)
	p.global_position = pos
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 0.7
	p.spread = 180.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0, 0.6, 0)
	var g := Gradient.new()
	g.set_color(0, col)
	g.set_color(1, Color(col, 0))
	p.color_ramp = g
	p.emitting = true
	_free_later(p, 1.5)


## Win: bottles hop in a wave and fireworks pop over them.
func celebrate() -> void:
	for i in bottles.size():
		var b: Bottle = bottles[i]
		var t := b.create_tween()
		t.tween_interval(0.07 * i)
		t.tween_property(b, "position", b.home + Vector3(0, 0.7, 0), 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		t.tween_callback(func(): b.celebrate())
		t.tween_property(b, "position", b.home, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		if not (state[i] as Array).is_empty():
			var col: Color = Game.PALETTE[state[i][0]]
			var tb := b.create_tween()
			tb.tween_interval(0.07 * i + 0.15)
			tb.tween_callback(func(): _burst(b.global_position + Vector3(0, float(b.prof.y_top) + 0.6, 0.3), col))


# =============================================================== undo / helpers

func undo() -> bool:
	if anims > 0 or history.is_empty():
		return false
	cancel_hint()
	if selected >= 0:
		_deselect()
	var snap: Dictionary = history.pop_back()
	state = snap.s
	hidden = snap.h
	moves = maxi(0, moves - 1)
	_done_flag = false
	for i in bottles.size():
		var b: Bottle = bottles[i]
		var was := b.corked
		b.set_units(state[i], hidden[i])
		b.corked = Puzzle.is_complete(state[i])
		b.cork.visible = b.corked
		if was and not b.corked:
			Sfx.play("uncork", 1.0, -6.0)
		b.kick(1.5)
	Sfx.play("undo", 1.0, -4.0)
	return true


func add_bottle() -> void:
	extra_added += 1
	state.append([])
	hidden.append([])
	for snap in history:
		snap.s.append([])
		snap.h.append([])
	var b := _spawn_bottle(state.size() - 1)
	layout(true)
	b.position = b.home + Vector3(0, 5, 0)
	b.scale = Vector3.ONE * 0.2
	var t := b.create_tween()
	t.tween_property(b, "position", b.home, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(b, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("powerup", 1.0, -4.0)


# =============================================================== hints

func _make_arrow() -> void:
	_arrow = Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.25)
	var cone := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.26
	c.bottom_radius = 0.0
	c.height = 0.38
	cone.mesh = c
	cone.material_override = mat
	_arrow.add_child(cone)
	var shaft := MeshInstance3D.new()
	var s := CylinderMesh.new()
	s.top_radius = 0.09
	s.bottom_radius = 0.09
	s.height = 0.4
	shaft.mesh = s
	shaft.position.y = 0.36
	shaft.material_override = mat
	_arrow.add_child(shaft)
	_arrow.visible = false
	add_child(_arrow)


func point_at(i: int) -> void:
	_arrow_target = i
	_arrow.visible = i >= 0


## Starts a time-sliced solver run; calls cb(Vector2i) with the move, or Vector2i(-1,-1).
func request_hint(cb: Callable) -> void:
	cancel_hint()
	_hint_solver = Puzzle.Solver.new(Puzzle.copy(state), 2.0)
	_hint_cb = cb
	_hint_t0 = Time.get_ticks_msec()


func show_hint(m: Vector2i) -> void:
	if selected >= 0 and selected != m.x:
		_deselect()
	if selected != m.x:
		_select(m.x)
	_hint_idx = m.x
	(bottles[m.x] as Bottle).set_hint(true)
	point_at(m.y)


func cancel_hint(clear_arrow := true) -> void:
	_hint_solver = null
	if _hint_idx >= 0 and _hint_idx < bottles.size():
		(bottles[_hint_idx] as Bottle).set_hint(false)
	_hint_idx = -1
	if clear_arrow:
		point_at(-1)
	else:
		point_at(-1)


func _process(_dt: float) -> void:
	if _hint_solver != null:
		var st: int = _hint_solver.step(500)
		if st != 0 or _hint_solver.expanded > 80000:
			var cb := _hint_cb
			var res: Array = _hint_solver.result if st == 1 else []
			_hint_solver = null
			cb.call(res[0] if not res.is_empty() else Vector2i(-1, -1))
	if _arrow.visible and _arrow_target >= 0 and _arrow_target < bottles.size():
		var b: Bottle = bottles[_arrow_target]
		var t := Time.get_ticks_msec() * 0.006
		_arrow.position = b.position + Vector3(0, float(b.prof.y_top) + 0.85 + 0.18 * sin(t), 0.3)
		_arrow.rotation.y = t * 0.5
