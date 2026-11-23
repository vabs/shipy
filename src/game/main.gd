extends Node
## Root of the game. Boots the router and handles dev command-line flags.
##
## Dev flags (pass after `--` on the godot command line):
##   --scene=<name>        start on this screen instead of "menu"
##   --level=<id>          level id passed to the screen as params.level
##   --phase=<port|voyage|results>  passed as params.phase
##   --autobuild           params.autobuild = true (auto-place a sensible ship)
##   --sim-seconds=<n>     params.sim_seconds (fast-forward voyage n seconds)
##   --seed=<n>            params.seed
##   --shot=<abs png path> save a screenshot after --frames frames, then quit
##   --frames=<n>          frames to wait before the screenshot (default 90)
##   --quit-after=<n>      quit after n frames without a screenshot
## Any other --key=value pair is passed through in params as a String.

var _shot_path: String = ""
var _frames_left: int = -1
var _quit_frames_left: int = -1


func _ready() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	Router.attach_root(self)
	if args.has("shot"):
		_shot_path = String(args["shot"])
		_frames_left = int(args.get("frames", "90"))
	if args.has("quit-after"):
		_quit_frames_left = int(args["quit-after"])
	var screen_name := String(args.get("scene", "menu"))
	var params := {}
	for k in args.keys():
		params[k] = args[k]
	if args.has("autobuild"):
		params["autobuild"] = true
	if args.has("sim-seconds"):
		params["sim_seconds"] = float(args["sim-seconds"])
	if args.has("seed"):
		params["seed"] = int(args["seed"])
	Router.goto(screen_name, params)


func _process(_delta: float) -> void:
	if _frames_left >= 0:
		_frames_left -= 1
		if _frames_left < 0:
			_take_shot()
	if _quit_frames_left >= 0:
		_quit_frames_left -= 1
		if _quit_frames_left < 0:
			get_tree().quit()


func _take_shot() -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_shot_path)
	if err != OK:
		push_error("Screenshot failed (%d): %s" % [err, _shot_path])
	else:
		print("SCREENSHOT_SAVED ", _shot_path)
	get_tree().quit()


static func _parse_args(raw: PackedStringArray) -> Dictionary:
	var out := {}
	for a in raw:
		if not a.begins_with("--"):
			continue
		var body := a.substr(2)
		var eq := body.find("=")
		if eq == -1:
			out[body] = "true"
		else:
			out[body.substr(0, eq)] = body.substr(eq + 1)
	return out
