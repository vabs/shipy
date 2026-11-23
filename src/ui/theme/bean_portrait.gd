class_name BeanPortrait
extends Control
## Round portrait of a guest or staff bean for roster cards / manifest.
##   prop: StringName (sun_hat|headband|glasses_3d|headphones), body_color: Color,
##   staff_role: StringName ("" guest | janitor | mechanic), mood: StringName ("" | happy|ok|unhappy|angry|sick|need_*),
##   plate_color: Color, portrait_size: float (px, square), selected: bool (coral ring).

const U := preload("res://src/render/art/art_util.gd")

var prop: StringName = &"sun_hat":
	set(v):
		prop = v
		queue_redraw()
var body_color: Color = Palette.PEACH:
	set(v):
		body_color = v
		queue_redraw()
var staff_role: StringName = &"":
	set(v):
		staff_role = v
		queue_redraw()
var mood: StringName = &"":
	set(v):
		mood = v
		queue_redraw()
var plate_color: Color = Color("CDEFFB"):
	set(v):
		plate_color = v
		queue_redraw()
var selected: bool = false:
	set(v):
		selected = v
		queue_redraw()
var portrait_size: float = 72.0:
	set(v):
		portrait_size = v
		custom_minimum_size = Vector2(v, v)
		queue_redraw()
var animate: bool = true:
	set(v):
		animate = v
		set_process(v)
var _t: float = randf() * 6.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(portrait_size, portrait_size)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	queue_redraw()


static func _mood_icon(m: StringName) -> StringName:
	match m:
		&"happy": return &"smile"
		&"ok": return &"meh"
		&"unhappy": return &"frown"
		&"angry": return &"angry"
		&"sick": return &"sick"
	if String(m).begins_with("need_"):
		return m
	return &""


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := Vector2(size.x * 0.5, size.y * 0.5)
	var r := s * 0.5 - 2.0
	U.circ(self, c + Vector2(0, 2), r, Color(0.1, 0.14, 0.26, 0.18))
	U.circ(self, c, r, plate_color)
	U.circ(self, c + Vector2(0, r * 0.55), r * 0.62, plate_color.lerp(Color.WHITE, 0.35))
	# the bean, drawn big, cropped by the circular plate
	var k := s / 46.0
	U.begin_scaled(self, c + Vector2(0, r * 0.62), k)
	var o := {"prop": prop, "body_color": body_color, "facing": 1, "walk_phase": 0.0, "pose": &"stand",
			"sick": mood == &"sick", "t": _t, "highlight": 0, "scale": 1.0}
	if staff_role != &"":
		o["role"] = staff_role
		GuestArt.draw_staff(self, Vector2.ZERO, o)
	else:
		GuestArt.draw_guest(self, Vector2.ZERO, o)
	U.end_scaled(self)
	var ring_c := Palette.CORAL if selected else Color(1, 1, 1, 0.9)
	U.arc(self, c, r, 0.0, TAU, ring_c, 4.0 if selected else 3.0, 40)
	var mi := _mood_icon(mood)
	if mi != &"":
		var bc := Vector2(size.x - s * 0.2, s * 0.2)
		U.circ(self, bc, s * 0.2, Color(1, 1, 1, 0.95))
		IconArt.draw_icon(self, mi, bc, s * 0.3, _t, false)
