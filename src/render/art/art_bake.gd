class_name ArtBake
extends Node
## Bakes static vector art into mipmapped textures (once, in a hidden SubViewport) so the per-frame cost of
## the ship is a handful of textured quads instead of thousands of draw commands.
##
## Usage (needs to live in the scene tree):
##   var baker := ArtBake.new(); add_child(baker)
##   baker.request(key, logical_size, scale, func(ci: CanvasItem) -> void: ...draw at (0,0)..logical_size...)
##   var tex := ArtBake.get_tex(key)     # null until baked (draw the vector fallback meanwhile)
##   signal baked(key)
## Textures are shared globally (static cache) so identical rooms / sprites bake only once.

signal baked(key: String)

static var _tex: Dictionary = {}
static var _pending: Dictionary = {}

var _vp: SubViewport
var _canvas: _Canvas
var _jobs: Array[Dictionary] = []
var _busy: bool = false
var _current_key: String = ""


class _Canvas extends Node2D:
	var cb: Callable = Callable()

	func _draw() -> void:
		if cb.is_valid():
			cb.call(self)


static func get_tex(key: String) -> Texture2D:
	return _tex.get(key)


static func has_tex(key: String) -> bool:
	return _tex.has(key)


static func is_pending(key: String) -> bool:
	return _pending.has(key)


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.disable_3d = true
	# The Compatibility renderer (web) has no 2D MSAA; requesting it only logs warnings.
	_vp.msaa_2d = Viewport.MSAA_DISABLED if OS.has_feature("web") else Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_vp.size = Vector2i(64, 64)
	add_child(_vp)
	_canvas = _Canvas.new()
	_vp.add_child(_canvas)
	_pump()


## Queue a bake. `logical_size` is the art-space size (px at zoom 1); texture resolution = size * scale.
func request(key: String, logical_size: Vector2, scale: float, cb: Callable) -> void:
	if _tex.has(key) or _pending.has(key):
		return
	_pending[key] = true
	_jobs.append({"key": key, "size": logical_size, "scale": scale, "cb": cb})
	_pump()


func _pump() -> void:
	if _busy or _jobs.is_empty() or _vp == null:
		return
	_busy = true
	var job: Dictionary = _jobs.pop_front()
	_run(job)


func _exit_tree() -> void:
	for j in _jobs:
		_pending.erase(j["key"])
	_jobs.clear()
	if _current_key != "":
		_pending.erase(_current_key)
		_current_key = ""


func _run(job: Dictionary) -> void:
	_current_key = job["key"]
	var sc: float = job["scale"]
	var lsz: Vector2 = job["size"]
	var px := Vector2i(maxi(int(ceil(lsz.x * sc)), 2), maxi(int(ceil(lsz.y * sc)), 2))
	_vp.size = px
	_canvas.scale = Vector2(sc, sc)
	_canvas.cb = job["cb"]
	_canvas.queue_redraw()
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var key: String = job["key"]
	var img := _vp.get_texture().get_image()
	if img != null and not img.is_empty():
		img.fix_alpha_edges()
		img.generate_mipmaps()
		_tex[key] = ImageTexture.create_from_image(img)
	_pending.erase(key)
	_current_key = ""
	_canvas.cb = Callable()
	_busy = false
	baked.emit(key)
	_pump()
