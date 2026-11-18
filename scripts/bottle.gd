class_name Bottle
extends Node3D
## One glass bottle: glass shell + cork from Blender, liquid mesh lathed from the cavity profile,
## liquid layers drawn by liquid.gdshader from per-layer volumes (in units, 1 unit = 1/4 bottle).

const LIQUID_SHADER := preload("res://shaders/liquid.gdshader")
const GLASS_SHADER := preload("res://shaders/glass.gdshader")
const MAX_SEG := 6

static var _liquid_meshes := {}
static var _scenes := {}
static var _font: Font

var kind := "flask"
var prof: Dictionary
var index := 0
var home := Vector3.ZERO
var selected := false
var busy := 0                       # number of running animations using this bottle
var segs: Array = []                # display layers: {c:int, v:float, hid:bool}, bottom -> top
var tilt := 0.0                     # degrees, lip side down
var tilt_dir := 1                   # +1: lip on +x (pours to the right)
var corked := false

var glass: MeshInstance3D
var cork: Node3D
var liquid: MeshInstance3D
var shadow: MeshInstance3D
var lmat: ShaderMaterial
var gmat: ShaderMaterial
var marks: Array[Label3D] = []
var _wob := Vector2.ZERO
var _wob_v := Vector2.ZERO
var _last_pos := Vector3.ZERO
var _last_vel := Vector3.ZERO
var _glow := 0.0
var _hint := 0.0
var _flash := 0.0


func setup(k: String, units: Array, hidden: Array) -> void:
	kind = k
	prof = Game.bottles[kind]
	if not _scenes.has(kind):
		_scenes[kind] = load("res://assets/models/bottle_%s.glb" % kind)
	var inst: Node3D = _scenes[kind].instantiate()
	var g := inst.find_child("Glass", true, false) as MeshInstance3D
	var c := inst.find_child("Cork", true, false) as MeshInstance3D
	glass = MeshInstance3D.new()
	glass.mesh = g.mesh
	gmat = ShaderMaterial.new()
	gmat.shader = GLASS_SHADER
	glass.material_override = gmat
	glass.sorting_offset = 0.5
	add_child(glass)
	cork = Node3D.new()
	var cm := MeshInstance3D.new()
	cm.mesh = c.mesh
	cork.add_child(cm)
	add_child(cork)
	cork.visible = false
	inst.free()

	liquid = MeshInstance3D.new()
	liquid.mesh = _liquid_mesh(kind, prof)
	lmat = ShaderMaterial.new()
	lmat.shader = LIQUID_SHADER
	liquid.material_override = lmat
	add_child(liquid)

	shadow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(prof.body_r * 3.2, prof.body_r * 1.6)
	q.orientation = PlaneMesh.FACE_Y
	shadow.mesh = q
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(0, 0, 0, 0.55))
	gr.set_color(1, Color(0, 0, 0, 0))
	gt.gradient = gr
	sm.albedo_texture = gt
	sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	shadow.material_override = sm
	shadow.position.y = 0.006
	add_child(shadow)
	set_units(units, hidden)


static func _liquid_mesh(k: String, p: Dictionary) -> ArrayMesh:
	if _liquid_meshes.has(k):
		return _liquid_meshes[k]
	var cav: Array = p.cavity
	var seg := 40
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for pt in cav:
		var r := maxf(float(pt[0]) - 0.008, 0.0)
		var y := float(pt[1]) + 0.004
		var ring: Array = []
		for i in seg + 1:
			var a := TAU * i / seg
			ring.append(Vector3(r * cos(a), y, r * sin(a)))
		rings.append(ring)
	for ri in rings.size() - 1:
		var a: Array = rings[ri]
		var b: Array = rings[ri + 1]
		for i in seg:
			st.add_vertex(a[i]); st.add_vertex(a[i + 1]); st.add_vertex(b[i + 1])
			st.add_vertex(a[i]); st.add_vertex(b[i + 1]); st.add_vertex(b[i])
	st.generate_normals()
	var m := st.commit()
	_liquid_meshes[k] = m
	return m


## Instantly show the model's contents.
func set_units(units: Array, hidden: Array) -> void:
	segs.clear()
	for i in units.size():
		var h := hidden.size() > i and int(hidden[i]) == 1
		var c := int(units[i])
		if not segs.is_empty() and segs[-1].c == c and not h and not segs[-1].hid:
			segs[-1].v += 1.0
		else:
			segs.append({"c": c, "v": 1.0, "hid": h})
	refresh()


func total_units() -> float:
	var t := 0.0
	for s in segs:
		t += s.v
	return t


# ---------------------------------------------------------------- volume tables

func surf_h(angle: float, v: float) -> float:
	var tb: Array = prof.table
	var fa := clampf(absf(angle) / float(prof.angle_step), 0.0, tb.size() - 1.001)
	var ia := int(fa)
	var ta := fa - ia
	var vs: int = int(prof.vsteps)
	var fv := clampf(v * vs, 0.0, vs - 0.0001)
	var iv := int(fv)
	var tv := fv - iv
	var r0: Array = tb[ia]
	var r1: Array = tb[ia + 1]
	var h0 := lerpf(float(r0[iv]), float(r0[iv + 1]), tv)
	var h1 := lerpf(float(r1[iv]), float(r1[iv + 1]), tv)
	return lerpf(h0, h1, ta)


## Tilt (degrees) at which liquid of the given number of units starts to pour out.
func pour_angle(units: float) -> float:
	var pa: Array = prof.pour_angle
	var f := clampf(units * float(prof.unit) * 64.0, 0.0, 63.999)
	var i := int(f)
	return lerpf(float(pa[i]), float(pa[i + 1]), f - i)


func lip_local() -> Vector3:
	return Vector3(tilt_dir * float(prof.neck_r), float(prof.y_top), 0)


func mouth_world() -> Vector3:
	return global_transform * Vector3(0, float(prof.y_top), 0)


## World height of the liquid surface (upright).
func surface_world_y() -> float:
	return global_position.y + surf_h(0.0, total_units() * float(prof.unit))


func set_tilt(deg: float, dir: int) -> void:
	tilt = deg
	tilt_dir = dir
	rotation.z = -dir * deg_to_rad(deg)


# ---------------------------------------------------------------- drawing

func refresh() -> void:
	var cols: Array = []
	var bnd: Array = []
	var hid: Array = []
	var unit := float(prof.unit)
	var cum := 0.0
	var n := 0
	bnd.append(surf_h(tilt, 0.0) - 0.02)
	for s in segs:
		if s.v <= 0.0005:
			continue
		if n >= MAX_SEG:
			break
		cum += s.v
		cols.append(Game.PALETTE[clampi(s.c, 0, Game.PALETTE.size() - 1)])
		hid.append(1.0 if s.hid else 0.0)
		bnd.append(surf_h(tilt, cum * unit))
		n += 1
	while cols.size() < MAX_SEG:
		cols.append(Color.BLACK)
		hid.append(0.0)
	while bnd.size() < MAX_SEG + 1:
		bnd.append(100.0)
	lmat.set_shader_parameter("colors", PackedColorArray(cols))
	lmat.set_shader_parameter("bounds", PackedFloat32Array(bnd))
	lmat.set_shader_parameter("hidden", PackedFloat32Array(hid))
	lmat.set_shader_parameter("nseg", n)
	_update_marks()


func _update_marks() -> void:
	var want: Array = []
	if absf(tilt) < 1.0:
		var cum := 0.0
		for s in segs:
			if s.hid and s.v > 0.5:
				var mid := surf_h(0.0, (cum + s.v * 0.5) * float(prof.unit))
				want.append(mid)
			cum += s.v
	while marks.size() < want.size():
		var l := Label3D.new()
		l.text = "?"
		if _font == null:
			_font = load("res://assets/fonts/Nunito.ttf")
		l.font = _font
		l.font_size = 96
		l.pixel_size = 0.0042
		l.outline_size = 18
		l.modulate = Color(1, 0.95, 0.75)
		l.outline_modulate = Color(0.1, 0.05, 0.2)
		l.no_depth_test = false
		l.render_priority = 2
		add_child(l)
		marks.append(l)
	for i in marks.size():
		var on := i < want.size()
		marks[i].visible = on
		if on:
			marks[i].position = Vector3(0, want[i], float(prof.body_r) + 0.02)


func set_selected(on: bool) -> void:
	selected = on
	var t := create_tween()
	t.tween_method(func(v): gmat.set_shader_parameter("select_glow", v), 1.0 - float(on), float(on), 0.18)


func set_hint(on: bool) -> void:
	_hint = 1.0 if on else 0.0
	if not on:
		gmat.set_shader_parameter("hint_glow", 0.0)


func flash(amount := 0.6) -> void:
	_flash = amount


func celebrate() -> void:
	_glow = 1.0


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	# slosh: a damped spring driven by the bottle's sideways acceleration
	# (frame time is clamped and sub-stepped: web/phones can stall for a long frame, which
	# would blow up an explicit spring)
	var dt := minf(delta, 1.0 / 30.0)
	var p := global_position
	var vel := (p - _last_pos) / dt
	if delta > 0.1:
		vel = Vector3.ZERO
	var acc := (vel - _last_vel) / dt
	_last_pos = p
	_last_vel = vel
	var force := Vector2(clampf(acc.x, -40, 40), clampf(acc.z, -40, 40)) * 0.27
	var steps := 4
	var h := dt / steps
	for k in steps:
		_wob_v += (-_wob * 90.0 - _wob_v * 7.0 + force) * h
		_wob += _wob_v * h
	_wob = _wob.limit_length(0.35)
	_wob_v = _wob_v.limit_length(4.0)
	var w := _wob if absf(tilt) < 0.5 else Vector2.ZERO
	lmat.set_shader_parameter("wobble", w)
	if _glow > 0.0:
		_glow = maxf(0.0, _glow - delta * 0.9)
		lmat.set_shader_parameter("glow", _glow)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.5)
		lmat.set_shader_parameter("flash", _flash)
	if _hint > 0.0:
		gmat.set_shader_parameter("hint_glow", 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.008))


func kick(amount: float) -> void:
	_wob_v.x += amount
