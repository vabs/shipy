extends Control
## Gallery page: SeaBackground + ShipCamera composition test with a placeholder ship silhouette.
## (The real ShipView is drawn by another agent; this page only judges the backdrop.)

var _dest: StringName = &"med"
var _sea: SeaBackground
var _cam: ShipCamera
var _ship: Node2D


func setup(dest: StringName) -> void:
	_dest = dest


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var world := Node2D.new()
	add_child(world)
	_sea = SeaBackground.attach_to(self)
	_sea.set_destination(_dest)
	# placeholder ship
	_ship = PlaceholderShip.new()
	if not "--noship" in OS.get_cmdline_user_args():
		world.add_child(_ship)
	_cam = ShipCamera.new()
	world.add_child(_cam)
	_cam.set_ship_rect(PlaceholderShip.RECT)
	_cam.set_insets(100.0, 220.0)
	_sea.bind_camera(_cam, 40.0)
	# fake HUD bars so the composition can be judged
	var hud := CanvasLayer.new()
	hud.layer = 10
	add_child(hud)
	var bars := HudBars.new()
	hud.add_child(bars)
	if "--camtest" in OS.get_cmdline_user_args():
		_camtest()


var _frames: int = 0


func _process(_dt: float) -> void:
	_frames += 1
	if "--bench" in OS.get_cmdline_user_args() and _frames == 300:
		print("BENCH fps=", Engine.get_frames_per_second(), " draw_calls=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		get_tree().quit()


func _camtest() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var p0 := Vector2(700, -200)
	print("CAM fit zoom=", _cam.zoom, " pos=", _cam.position, " p0 screen=", _cam.local_to_screen(p0))
	_cam.zoom_in()
	for i in range(90):
		await get_tree().process_frame
	print("CAM lvl1 zoom=", _cam.zoom, " pos=", _cam.position, " p0 screen=", _cam.local_to_screen(p0), " back=", _cam.screen_to_local(_cam.local_to_screen(p0)))
	_cam.focus_on(Vector2(100, -100), 2)
	for i in range(120):
		await get_tree().process_frame
	print("CAM lvl2 zoom=", _cam.zoom, " pos=", _cam.position, " scr(100,-100)=", _cam.local_to_screen(Vector2(100, -100)))
	_cam.focus_on(Vector2(-5000, 5000))
	for i in range(120):
		await get_tree().process_frame
	print("CAM clamped pos=", _cam.position)
	_cam.fit()
	for i in range(120):
		await get_tree().process_frame
	print("CAM fit again zoom=", _cam.zoom, " pos=", _cam.position)


class PlaceholderShip extends Node2D:
	const RECT := Rect2(-70, -560, 1450, 680)
	var _t: float = 0.0

	func _process(dt: float) -> void:
		_t += dt
		position.y = sin(_t * TAU * 0.22) * 3.0
		rotation = sin(_t * TAU * 0.22 + 1.0) * deg_to_rad(0.5)
		queue_redraw()

	func _draw() -> void:
		var w: float = 1280.0
		# superstructure behind the top deck
		draw_rect(Rect2(w * 0.55, -440, 210, 70), Palette.HULL_WHITE)
		draw_rect(Rect2(w * 0.55 + 20, -420, 170, 22), Palette.TEAL_LIGHT)
		draw_rect(Rect2(w * 0.3, -450, 70, 80), Palette.CORAL)
		draw_rect(Rect2(w * 0.3, -450, 70, 14), Palette.NAVY)
		for i in range(3):
			draw_circle(Vector2(w * 0.3 + 35 + sin(_t + i) * 6, -470 - i * 26 - _t * 0.0), 14 + i * 4, Color(1, 1, 1, 0.8 - i * 0.2))
		# decks
		for d in range(5):
			var y: float = -76.0 * float(d + 1)
			if d == 4:
				draw_rect(Rect2(0, y + 64, w, 12), Palette.FLOOR_TOP)
				continue
			draw_rect(Rect2(0, y, w, 76), Palette.WALL_MAIN)
			draw_rect(Rect2(0, y, w, 6), Palette.CEILING_TRIM)
			draw_rect(Rect2(0, y + 65, w, 11), Palette.FLOOR_TOP)
			for c in range(32):
				draw_rect(Rect2(c * 40 + 12, y + 22, 16, 24), Palette.GLASS)
		# hull
		var hull := PackedVector2Array([Vector2(-14, 0), Vector2(w + 36, 0), Vector2(w + 10, 40), Vector2(w - 70, 66), Vector2(50, 66), Vector2(-4, 36)])
		draw_colored_polygon(hull, Palette.NAVY)
		draw_rect(Rect2(-6, 30, w + 22, 10), Palette.CORAL)
		for i in range(22):
			draw_circle(Vector2(50 + i * 56, 15), 7, Palette.GLASS)


class HudBars extends Control:
	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s: Vector2 = get_viewport_rect().size
		draw_rect(Rect2(0, 0, s.x, 90), Color(Palette.NAVY, 0.85))
		draw_rect(Rect2(0, s.y - 210, s.x, 210), Color(Palette.NAVY, 0.85))
