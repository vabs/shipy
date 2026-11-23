extends Node
## Screen router (autoload "Router").
##
## Screens are plain scripts (no .tscn) living at
##   res://src/screens/<name>/<name>_screen.gd
## Each screen script must extend Control or Node2D/Node and may implement
##   func setup(params: Dictionary) -> void   # called BEFORE it enters the tree
## Known screen names: "menu", "map", "level", "settings", "gallery" (dev only).

signal screen_changed(screen_name: String)

var current_name: String = ""
var current: Node = null
var _root: Node = null


## Called by Main once the main scene is ready.
func attach_root(root: Node) -> void:
	_root = root


func goto(screen_name: String, params: Dictionary = {}) -> void:
	if _root == null:
		push_error("Router.goto called before attach_root")
		return
	var path := "res://src/screens/%s/%s_screen.gd" % [screen_name, screen_name]
	if not ResourceLoader.exists(path):
		push_error("Router: unknown screen '%s' (%s)" % [screen_name, path])
		return
	var script: Script = load(path)
	var screen: Node = script.new()
	screen.name = screen_name.capitalize().replace(" ", "") + "Screen"
	if screen.has_method("setup"):
		screen.call("setup", params)
	if current != null:
		current.queue_free()
	current = screen
	current_name = screen_name
	_root.add_child(screen)
	screen_changed.emit(screen_name)
