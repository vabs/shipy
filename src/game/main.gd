extends Node
## Root of the game. Boots the router and handles dev command-line flags.
##
## Dev flags (pass after `--` on the godot command line):
##   --scene=<name>        start on this screen instead of "menu" (menu, map, shipyard, level, settings, gallery)
##   --level=<id>          level id passed to the screen as params.level
##   --phase=<port|voyage|results>  passed as params.phase (results: add --autoplay=active|human|passive; --showreport opens
##                         the Voyage report, --heatmap[=traffic|unhappy|queue] the heatmap; port: --lastvoyage[=on] shows the
##                         "Last voyage" heatmap toggle)
##   --autobuild           params.autobuild = true (auto-place a sensible ship)
##   --sim-seconds=<n>     params.sim_seconds (fast-forward voyage n seconds)
##   --seed=<n>            params.seed
##   --crew=<role:n,...>   level: replace the crew (e.g. janitor:1,medic:1,chef:1,entertainer:1,warden:1); --tab=<id> port tab
##   --tired=<energy>      level voyage: crew start with this energy (staff fatigue levels);
##                         --sicken=<n> / --ghosts=<n> make n guests ill / spawn n ghosts after the fast-forward
##   --vips=<kind:t,...>   level: board VIPs (critic | celebrity | inspector) at second t, e.g. critic:20,celebrity:40,inspector:60
##   --groups=<0..1>       level: that share of every wave boards as couples / families with kids (needs a kids' club)
##   --stage=vips          level voyage (use with --speed=0, --vips and --groups): freezes a showcase on the ship: every VIP kind,
##                         a family with a kid in the ball pit, the heart link on a hovered member, a verdict plate
##   --page=crew           gallery: every crew role in every pose plus the crew quarters
##   --page=vips           gallery: the kid, the three VIPs, the group pins and the kids' club
##   --storm=<t>           level (voyage): a storm hits at second t (45 s: top deck closed, seasick guests, rain + lightning, ship rolls). Use with
##                         --phase=voyage --autobuild --sim-seconds=<t+20> --speed=0 to look at the peak
##   --portstop=<t>        level (voyage): a mid-voyage port stop at second t: docking banner, 40% of the guests go ashore, the sim pauses with the
##                         Quick refit panel, "Cast off!" boards new guests. --portname=<name> --disembark=<0..1> --board=<n> tune it;
##                         --selftest=portstop drives the refit with real input (place a room, upgrade one, cast off)
##   --save=<abs json path> load a scratch save (funds / perks / stars) instead of the real one (menu, map, shipyard, level)
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
