extends SceneTree
## Renders the in-code title logo (MenuLogo) to assets/splash.png for the boot splash, which replaces
## Godot's default logo on desktop and the web loading screen. Needs a display (not --headless):
##   godot --path . --script res://tools/bake_splash.gd
## The PNG is transparent; project.godot's boot_splash/bg_color supplies the sky-blue backdrop.

const OUT: String = "res://assets/splash.png"
const CANVAS: Vector2i = Vector2i(1920, 1080)
const LOGO_SCALE: float = 1.5


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = CANVAS
	vp.transparent_bg = true
	vp.msaa_2d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var logo := MenuLogo.new()
	vp.add_child(logo)
	logo.set_process(false)  # freeze the idle bounce; letters and ribbon fully landed
	logo.intro_t = 10.0
	logo.size = logo.custom_minimum_size
	logo.scale = Vector2.ONE * LOGO_SCALE
	# Sit a touch above centre so the logo reads optically centred.
	logo.position = (Vector2(CANVAS) - logo.size * LOGO_SCALE) * 0.5 - Vector2(0, 30)
	logo.queue_redraw()

	for i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	var err: Error = img.save_png(ProjectSettings.globalize_path(OUT))
	print("bake_splash: wrote %s (%dx%d) err=%d" % [OUT, img.get_width(), img.get_height(), err])
	quit(0 if err == OK else 1)
