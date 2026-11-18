class_name UiKit
extends RefCounted
## UI built in code: fonts, glossy buttons, vector icons, stars, panels. No .tscn needed.

static var font_body: Font
static var font_title: Font
static var theme: Theme


static func init_theme() -> Theme:
	if theme:
		return theme
	var base: FontFile = load("res://assets/fonts/Nunito.ttf")
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 850}
	font_body = fv
	font_title = load("res://assets/fonts/Lobster.ttf")
	theme = Theme.new()
	theme.default_font = font_body
	theme.default_font_size = 34
	return theme


static func label(text: String, size := 40, color := Color.WHITE, outline := 10, title := false) -> Label:
	var l := Label.new()
	l.text = text
	if title:
		l.add_theme_font_override("font", font_title)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.02, 0.15, 0.95))
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_y", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func box(bg: Color, border: Color, radius: int, bw := 4, glow := 0.0, bg2 := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	s.corner_detail = 12
	if glow > 0.0:
		s.shadow_color = Color(border, glow)
		s.shadow_size = 16
	s.content_margin_left = 24
	s.content_margin_right = 24
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


static func style_button(b: Button, color: Color, radius: int) -> void:
	b.add_theme_stylebox_override("normal", box(color.darkened(0.25), color.lightened(0.45), radius, 4, 0.35))
	b.add_theme_stylebox_override("hover", box(color.darkened(0.1), color.lightened(0.6), radius, 4, 0.55))
	b.add_theme_stylebox_override("pressed", box(color.darkened(0.4), color.lightened(0.7), radius, 4, 0.75))
	b.add_theme_stylebox_override("disabled", box(Color(0.16, 0.14, 0.22, 0.9), Color(0.35, 0.32, 0.45), radius, 3))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.5, 0.65))
	b.add_theme_color_override("font_outline_color", Color(0.08, 0.02, 0.15, 0.9))
	b.add_theme_constant_override("outline_size", 9)


static func button(text: String, color: Color, size := Vector2(400, 108), font := 46) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.add_theme_font_size_override("font_size", font)
	style_button(b, color, int(size.y * 0.5))
	juice(b)
	return b


## Squash on press, elastic pop on release, click sound.
static func juice(b: Control) -> void:
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	if b is BaseButton:
		var bb: BaseButton = b
		bb.button_down.connect(func():
			var t := b.create_tween()
			t.tween_property(b, "scale", Vector2(0.88, 0.88), 0.06))
		bb.button_up.connect(func():
			var t := b.create_tween()
			t.tween_property(b, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))
		bb.pressed.connect(func(): Sfx.play("click"))


static func pop_in(c: Control, delay := 0.0, dur := 0.45) -> void:
	c.scale = Vector2(0.01, 0.01)
	var t := c.create_tween()
	t.tween_interval(delay)
	t.tween_callback(func(): c.pivot_offset = c.size * 0.5)
	t.tween_property(c, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func panel(color := Color(0.45, 0.25, 0.85)) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(Color(0.1, 0.05, 0.2, 0.92), color.lightened(0.3), 44, 5, 0.5)
	s.content_margin_left = 36
	s.content_margin_right = 36
	s.content_margin_top = 30
	s.content_margin_bottom = 34
	p.add_theme_stylebox_override("panel", s)
	return p


# ------------------------------------------------------------- icon button

class IconButton extends Button:
	var kind := "undo"
	var off := false
	var tint := Color.WHITE
	var badge := ""

	func _init(k: String, color: Color, d := 108.0) -> void:
		kind = k
		tint = color
		custom_minimum_size = Vector2(d, d)
		UiKit.style_button(self, color, int(d * 0.5))
		UiKit.juice(self)

	func set_badge(t: String) -> void:
		badge = t
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.24
		var w := maxf(4.0, r * 0.22)
		var col := Color(1, 1, 1, 0.45) if disabled else Color.WHITE
		match kind:
			"undo":
				draw_arc(c + Vector2(r * 0.15, r * 0.1), r, -PI * 0.75, PI * 0.6, 24, col, w, true)
				var a := c + Vector2(r * 0.15, r * 0.1) + Vector2(cos(-PI * 0.75), sin(-PI * 0.75)) * r
				draw_colored_polygon(PackedVector2Array([a + Vector2(-r * 0.6, -r * 0.05), a + Vector2(r * 0.25, -r * 0.5), a + Vector2(r * 0.15, r * 0.45)]), col)
			"restart":
				draw_arc(c, r, -PI * 0.35, PI * 1.45, 28, col, w, true)
				var a := c + Vector2(cos(-PI * 0.35), sin(-PI * 0.35)) * r
				draw_colored_polygon(PackedVector2Array([a + Vector2(-r * 0.45, -r * 0.3), a + Vector2(r * 0.45, -r * 0.35), a + Vector2(0.1 * r, r * 0.45)]), col)
			"hint":
				draw_circle(c + Vector2(0, -r * 0.25), r * 0.72, col)
				draw_rect(Rect2(c + Vector2(-r * 0.36, r * 0.35), Vector2(r * 0.72, r * 0.5)), col)
				draw_line(c + Vector2(-r * 0.3, r * 0.62), c + Vector2(r * 0.3, r * 0.62), tint.darkened(0.5), 3)
				draw_rect(Rect2(c + Vector2(-r * 0.22, r * 0.9), Vector2(r * 0.44, r * 0.22)), col)
			"bottle":
				var body := PackedVector2Array([c + Vector2(-r * 0.6, -r * 0.2), c + Vector2(-r * 0.25, -r * 0.55), c + Vector2(-r * 0.25, -r * 1.0),
					c + Vector2(r * 0.25, -r * 1.0), c + Vector2(r * 0.25, -r * 0.55), c + Vector2(r * 0.6, -r * 0.2), c + Vector2(r * 0.6, r * 1.0), c + Vector2(-r * 0.6, r * 1.0)])
				var outline := body.duplicate()
				outline.append(body[0])
				draw_polyline(outline, col, w * 0.8, true)
				draw_rect(Rect2(c + Vector2(-r * 0.45, r * 0.25), Vector2(r * 0.9, r * 0.62)), Color(0.4, 0.9, 1.0, col.a))
				draw_line(c + Vector2(r * 0.95, -r * 0.6), c + Vector2(r * 0.95, r * 0.0), col, w * 0.8)
				draw_line(c + Vector2(r * 0.65, -r * 0.3), c + Vector2(r * 1.25, -r * 0.3), col, w * 0.8)
			"home":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 1.05), c + Vector2(r * 1.1, -r * 0.05), c + Vector2(-r * 1.1, -r * 0.05)]), col)
				draw_rect(Rect2(c + Vector2(-r * 0.75, -r * 0.1), Vector2(r * 1.5, r * 1.0)), col)
				draw_rect(Rect2(c + Vector2(-r * 0.22, r * 0.3), Vector2(r * 0.44, r * 0.6)), tint.darkened(0.4))
			"levels":
				for yy in 3:
					for xx in 3:
						draw_rect(Rect2(c + Vector2((xx - 1.5) * r * 0.72 + r * 0.06, (yy - 1.5) * r * 0.72 + r * 0.06), Vector2(r * 0.55, r * 0.55)), col)
			"gear":
				for k in 8:
					var ang := k * TAU / 8.0
					var d := Vector2(cos(ang), sin(ang))
					draw_line(c + d * r * 0.6, c + d * r * 1.05, col, r * 0.42)
				draw_circle(c, r * 0.72, col)
				draw_circle(c, r * 0.3, tint.darkened(0.3))
			"play":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.6, -r * 0.9), c + Vector2(r * 0.95, 0), c + Vector2(-r * 0.6, r * 0.9)]), col)
			"back":
				draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.55, -r * 0.9), c + Vector2(-r * 0.85, 0), c + Vector2(r * 0.55, r * 0.9)]), col)
			"next":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.55, -r * 0.9), c + Vector2(r * 0.85, 0), c + Vector2(-r * 0.55, r * 0.9)]), col)
			"close":
				draw_line(c + Vector2(-r * 0.7, -r * 0.7), c + Vector2(r * 0.7, r * 0.7), col, w * 1.2)
				draw_line(c + Vector2(r * 0.7, -r * 0.7), c + Vector2(-r * 0.7, r * 0.7), col, w * 1.2)
			"sound", "music":
				if kind == "sound":
					draw_colored_polygon(PackedVector2Array([c + Vector2(-r, -r * 0.35), c + Vector2(-r * 0.45, -r * 0.35), c + Vector2(r * 0.1, -r * 0.9), c + Vector2(r * 0.1, r * 0.9), c + Vector2(-r * 0.45, r * 0.35), c + Vector2(-r, r * 0.35)]), col)
					if not off:
						draw_arc(c + Vector2(r * 0.1, 0), r * 0.5, -PI * 0.3, PI * 0.3, 10, col, w * 0.7, true)
						draw_arc(c + Vector2(r * 0.1, 0), r * 0.95, -PI * 0.3, PI * 0.3, 12, col, w * 0.7, true)
				else:
					draw_circle(c + Vector2(-r * 0.45, r * 0.6), r * 0.33, col)
					draw_circle(c + Vector2(r * 0.55, r * 0.4), r * 0.33, col)
					draw_line(c + Vector2(-r * 0.15, r * 0.6), c + Vector2(-r * 0.15, -r * 0.8), col, w * 0.7)
					draw_line(c + Vector2(r * 0.85, r * 0.4), c + Vector2(r * 0.85, -r * 1.0), col, w * 0.7)
					draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.15, -r * 0.8), c + Vector2(r * 0.85, -r * 1.0), c + Vector2(r * 0.85, -r * 0.6), c + Vector2(-r * 0.15, -r * 0.4)]), col)
				if off:
					draw_line(c + Vector2(-r * 1.1, -r * 1.1), c + Vector2(r * 1.1, r * 1.1), Color(1, 0.35, 0.35), w)
		if badge != "":
			var f := UiKit.font_body
			var fs := int(size.y * 0.26)
			var tw := f.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var bw := maxf(tw + 18.0, size.y * 0.4)
			var br := Rect2(Vector2(size.x - bw + 6, size.y - size.y * 0.4 + 6), Vector2(bw, size.y * 0.4))
			var sb := UiKit.box(Color(0.9, 0.2, 0.35), Color.WHITE, int(br.size.y * 0.5), 3)
			draw_style_box(sb, br)
			draw_string(f, Vector2(br.position.x + (bw - tw) * 0.5, br.position.y + br.size.y * 0.75), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


# ------------------------------------------------------------- star

class Star extends Control:
	var filled := true
	var col := Color(1, 0.8, 0.15)

	func _init(d := 64.0, f := true) -> void:
		custom_minimum_size = Vector2(d, d)
		filled = f
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var R := minf(size.x, size.y) * 0.5
		var pts := PackedVector2Array()
		for k in 10:
			var ang := -PI / 2.0 + k * PI / 5.0
			var rr := R if k % 2 == 0 else R * 0.46
			pts.append(c + Vector2(cos(ang), sin(ang)) * rr)
		var outline := pts.duplicate()
		outline.append(pts[0])
		if filled:
			draw_colored_polygon(pts, col)
			draw_circle(c + Vector2(-R * 0.18, -R * 0.2), R * 0.13, Color(1, 1, 1, 0.75))
			draw_polyline(outline, col.darkened(0.55), maxf(2.0, R * 0.08), true)
		else:
			draw_colored_polygon(pts, Color(0.12, 0.08, 0.2, 0.85))
			draw_polyline(outline, Color(0.5, 0.42, 0.65), maxf(2.0, R * 0.06), true)


static func star_row(n: int, d := 30.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 2)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in 3:
		h.add_child(Star.new(d, k < n))
	return h


class Lock extends Control:
	func _init(d := 40.0) -> void:
		custom_minimum_size = Vector2(d, d)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var col := Color(0.75, 0.68, 0.85)
		draw_arc(c + Vector2(0, -r * 0.15), r * 0.45, PI, TAU, 16, col, r * 0.16, true)
		draw_style_box(UiKit.box(col, col, int(r * 0.2), 0), Rect2(c + Vector2(-r * 0.7, -r * 0.15), Vector2(r * 1.4, r * 1.0)))
		draw_circle(c + Vector2(0, r * 0.3), r * 0.15, Color(0.2, 0.15, 0.3))


## Text on a soft dark pill (toasts, tutorial lines).
static func pill(size := 32) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(Color(0.06, 0.02, 0.14, 0.82), Color(1, 0.85, 0.4, 0.8), 30, 2)
	s.content_margin_left = 28
	s.content_margin_right = 28
	s.content_margin_top = 10
	s.content_margin_bottom = 12
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label("", size, Color(1, 0.97, 0.85), 6)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.name = "L"
	p.add_child(l)
	return p


## Small tilted potion bottle drawn for the level buttons / decoration.
class Potion extends Control:
	var col := Color(0.4, 0.8, 1.0)
	var fill := 0.6

	func _init(d := 60.0, c := Color.WHITE, f := 0.6) -> void:
		custom_minimum_size = Vector2(d, d * 1.3)
		col = c
		fill = f
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var body := Rect2(Vector2(w * 0.18, h * 0.38), Vector2(w * 0.64, h * 0.58))
		var liq := Rect2(Vector2(body.position.x, body.end.y - body.size.y * fill), Vector2(body.size.x, body.size.y * fill))
		draw_style_box(UiKit.box(col, col, int(w * 0.18), 0), liq)
		draw_style_box(UiKit.box(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.8), int(w * 0.2), 3), body)
		draw_rect(Rect2(Vector2(w * 0.36, h * 0.16), Vector2(w * 0.28, h * 0.24)), Color(1, 1, 1, 0.8), false, 3)
		draw_rect(Rect2(Vector2(w * 0.33, h * 0.06), Vector2(w * 0.34, h * 0.12)), Color(0.75, 0.5, 0.3))
		draw_line(Vector2(body.position.x + w * 0.1, body.position.y + h * 0.08), Vector2(body.position.x + w * 0.1, body.end.y - h * 0.1), Color(1, 1, 1, 0.6), 3)
