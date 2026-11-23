extends Control
## Dev gallery (docs/SPEC.md §10). `--scene=gallery --page=<rooms|guests|icons|ship|ui|sea> --dest=<med|arctic|underworld>`
## Each page lives in page_<name>.gd (a Control/Node2D with optional setup(dest: StringName) and
## optional setup_params(params: Dictionary) for extra --key=value flags).

var _page: String = "rooms"
var _dest: StringName = &"med"
var _params: Dictionary = {}


func setup(params: Dictionary) -> void:
	_params = params
	_page = String(params.get("page", "rooms"))
	_dest = StringName(String(params.get("dest", "med")))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var path := "res://src/screens/gallery/page_%s.gd" % _page
	if not ResourceLoader.exists(path):
		push_error("Gallery: unknown page '%s'" % _page)
		return
	var script: Script = load(path)
	var page: Node = script.new()
	if page.has_method("setup"):
		page.call("setup", _dest)
	if page.has_method("setup_params"):
		page.call("setup_params", _params)
	add_child(page)
