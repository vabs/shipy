extends Node2D
## Gallery page: all props x poses, moods (sick/slip/storm), staff.

const U := preload("res://src/render/art/art_util.gd")
var _t: float = 0.0
var _dest: StringName = &"med"


func setup(dest: StringName) -> void:
	_dest = dest


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var d := Palette.dest(_dest)
	U.vgrad(self, Rect2(0, 0, 1920, 1080), d["sky_top"], d["sky_bottom"])
	U.rr(self, Rect2(30, 30, 1860, 1020), 24, Palette.CREAM)
	var f := U.font_bold()
	var props: Array[StringName] = [&"sun_hat", &"headband", &"glasses_3d", &"headphones"]
	var colors: Array[Color] = [Palette.archetype_color(&"holidaymaker"), Palette.archetype_color(&"fitness_fan"), Palette.archetype_color(&"film_buff"), Palette.archetype_color(&"gamer")]
	var poses: Array[StringName] = [&"stand", &"walk", &"queue", &"sit", &"swim", &"lie", &"sleep", &"run", &"slip", &"storm"]
	var scale := 3.0
	var x0 := 180.0
	for pi in range(poses.size()):
		U.text(self, String(poses[pi]), Vector2(x0 + pi * 160 - 30, 70), 22, Palette.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
	for r in range(props.size()):
		U.text(self, String(props[r]), Vector2(60, 180 + r * 130), 18, Palette.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
		for pi in range(poses.size()):
			var feet := Vector2(x0 + pi * 160 + 40, 190 + r * 130)
			var o := {"prop": props[r], "body_color": colors[r], "facing": 1, "walk_phase": _t * 9.0, "pose": poses[pi], "t": _t, "scale": 2.4, "slip_t": fmod(_t, 2.2)}
			GuestArt.draw_guest(self, feet, o)
	# zoom-1 row
	U.text(self, "zoom 1", Vector2(60, 700), 18, Palette.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
	for pi in range(poses.size()):
		for r in range(4):
			var feet := Vector2(x0 + pi * 160 + 10 + r * 22, 700)
			GuestArt.draw_guest(self, feet, {"prop": props[r], "body_color": colors[r], "facing": -1 if r % 2 == 1 else 1, "walk_phase": _t * 9.0 + r, "pose": poses[pi], "t": _t, "slip_t": fmod(_t, 2.2)})
	# sick / highlights
	U.text(self, "sick / hover / selected / queue facing", Vector2(60, 770), 18, Palette.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
	for i in range(4):
		GuestArt.draw_guest(self, Vector2(200 + i * 120, 860), {"prop": props[i], "body_color": colors[i], "pose": &"stand", "sick": i == 0, "highlight": i if i > 0 and i < 3 else 0, "t": _t, "scale": 2.4})
	# staff
	for i in range(8):
		var role: StringName = &"janitor" if i < 4 else &"mechanic"
		var poseS: StringName = [&"stand", &"walk", &"work", &"run"][i % 4]
		GuestArt.draw_staff(self, Vector2(760 + i * 120, 860), {"role": role, "pose": poseS, "facing": 1, "walk_phase": _t * 9.0, "t": _t, "scale": 2.4, "highlight": 2 if i == 2 else 0})
	for i in range(8):
		var role2: StringName = &"janitor" if i < 4 else &"mechanic"
		var poseS2: StringName = [&"stand", &"walk", &"work", &"run"][i % 4]
		GuestArt.draw_staff(self, Vector2(760 + i * 60, 980), {"role": role2, "pose": poseS2, "facing": -1, "walk_phase": _t * 9.0, "t": _t})
