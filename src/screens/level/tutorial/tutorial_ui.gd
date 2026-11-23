class_name TutorialUI
extends CanvasLayer
## Everything the tutorial draws, on its own CanvasLayer above the HUD: soft spotlight, pulsing ring + arrow,
## the captain's speech bubble and a small "Skip tutorial" chip for the moments when no bubble is up.
## Nothing here blocks the mouse except the bubble's own buttons.
##
##   set_targets(targets)   targets: Array[Dictionary] {rect: Rect2 (viewport px), radius := 18.0, pad := 8.0, arrow := true}
##   set_bounds(top, bottom)   vertical band (viewport px) the bubble may use
##   show_step(...) / hide_step() / celebrate()  /  set_dim(f)

signal next_pressed
signal skip_pressed

const SLOT_ORDER: Array[int] = [0, 1, 2, 3, 4, 5]

var root: Control
var spot: TutorialSpotlight
var pointer: TutorialPointer
var card: TutorialCard
var chip: PanelContainer
var bounds_top: float = 104.0
var bounds_bottom: float = 880.0
var card_shown: bool = false

var _cur: Array[Rect2] = []
var _tgt: Array[Rect2] = []
var _rad: Array[float] = []
var _arrow: Array[bool] = []
var _closing: Array[float] = []
var _slot: int = -1
var _card_pos: Vector2 = Vector2.ZERO
var _placed: bool = false
var _praise_idx: int = 0


func _init() -> void:
	layer = 30
	name = "TutorialLayer"


func _ready() -> void:
	root = Control.new()
	root.name = "TutorialRoot"
	root.theme = UITheme.build()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	spot = TutorialSpotlight.new()
	root.add_child(spot)
	pointer = TutorialPointer.new()
	root.add_child(pointer)
	card = TutorialCard.new()
	card.visible = false
	card.next_pressed.connect(func() -> void: next_pressed.emit())
	card.skip_pressed.connect(func() -> void: skip_pressed.emit())
	root.add_child(card)
	chip = _make_chip()
	chip.visible = false
	root.add_child(chip)


func _make_chip() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"PillPanel"
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var hb := UIKit.hbox(8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var iv := GlyphView.new(&"star", 22.0)
	hb.add_child(iv)
	var b := Button.new()
	b.text = "Skip tutorial"
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", UITheme.font_bold())
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", Palette.SUN)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, UITheme.empty(Vector4(6, 0, 6, 0)))
	b.pressed.connect(func() -> void:
		AudioManager.play_sfx(&"ui_click")
		skip_pressed.emit())
	hb.add_child(b)
	p.add_child(hb)
	p.set_meta(&"skip", b)
	return p


# ---- API --------------------------------------------------------------------------------------
func set_bounds(top: float, bottom: float) -> void:
	bounds_top = top
	bounds_bottom = bottom


func set_dim(v: float) -> void:
	spot.dim = v


func show_step(text: String, index: int, count: int, next_label: String) -> void:
	card_shown = true
	chip.visible = false
	card.show_step(text, index, count, next_label)
	AudioManager.play_sfx(&"ui_hover", 0.0, -3.0)
	_placed = false


func hide_step() -> void:
	card_shown = false
	card.disappear()
	chip.visible = true
	set_targets([])


func celebrate(word: String = "") -> void:
	if word == "":
		var words: Array[String] = ["Nice!", "Great!", "Perfect!", "Well done!", "Smooth sailing!"]
		word = words[_praise_idx % words.size()]
		_praise_idx += 1
	if card_shown:
		card.praise(word)
	pointer.flash()
	AudioManager.play_sfx(&"star_1", 0.0, -5.0)


func set_targets(targets: Array) -> void:
	var n: int = mini(targets.size(), TutorialSpotlight.MAX_HOLES)
	_tgt.clear()
	_rad.clear()
	_arrow.clear()
	for i in n:
		var d: Dictionary = targets[i]
		var r: Rect2 = d["rect"]
		var pad: float = float(d.get("pad", 8.0))
		_tgt.append(r.grow(pad))
		_rad.append(float(d.get("radius", 18.0)) + pad * 0.5)
		_arrow.append(bool(d.get("arrow", true)))
	# grow / shrink the smoothed lists
	while _cur.size() > n:
		_cur.pop_back()
		_closing.pop_back()
	while _cur.size() < n:
		_cur.append(_tgt[_cur.size()])
		_closing.append(1.0)


# ---- per frame --------------------------------------------------------------------------------
func _process(delta: float) -> void:
	var k: float = 1.0 - exp(-16.0 * delta)
	var holes: Array[Rect2] = []
	for i in _cur.size():
		var t: Rect2 = _tgt[i]
		var c: Rect2 = _cur[i]
		c = Rect2(c.position.lerp(t.position, k), c.size.lerp(t.size, k))
		_cur[i] = c
		_closing[i] = move_toward(_closing[i], 0.0, delta * 3.2)
		holes.append(c.grow(ease(_closing[i], 2.2) * 90.0))
	spot.set_holes(holes, _rad)
	pointer.rects = holes
	pointer.radii = _rad
	pointer.arrows = _arrow
	pointer.active = true
	_place_card(delta)
	if chip.visible:
		chip.reset_size()
		chip.position = Vector2(24.0, bounds_bottom - chip.size.y - 6.0)


func _place_card(delta: float) -> void:
	if not card_shown:
		pointer.avoid = Rect2()
		return
	var vp: Vector2 = root.size
	var cs: Vector2 = card.size
	if cs.x < 10.0:
		return
	var margin: float = 24.0
	var top_y: float = bounds_top + 8.0
	var bot_y: float = bounds_bottom - cs.y - 10.0
	var cand: Array[Vector2] = [
		Vector2(margin, top_y),
		Vector2(vp.x - margin - cs.x, top_y),
		Vector2(margin, bot_y),
		Vector2(vp.x - margin - cs.x, bot_y),
		Vector2((vp.x - cs.x) * 0.5, top_y),
		Vector2((vp.x - cs.x) * 0.5, bot_y),
	]
	var scores: Array[float] = []
	for p in cand:
		scores.append(_overlap(Rect2(p, cs)))
	var best: int = 0
	for i in cand.size():
		if scores[i] < scores[best] - 1.0:
			best = i
	if _slot < 0 or scores[_slot] > scores[best] + 1.0:
		_slot = best
	var goal: Vector2 = cand[_slot]
	if not _placed:
		_card_pos = goal
		_placed = true
	else:
		_card_pos = _card_pos.lerp(goal, 1.0 - exp(-12.0 * delta))
	card.position = _card_pos
	pointer.avoid = Rect2(_card_pos, cs)


func _overlap(r: Rect2) -> float:
	var total: float = 0.0
	for t in _tgt:
		var z: Rect2 = t.grow(46.0)
		var ix: Rect2 = r.intersection(z)
		if ix.size.x > 0.0 and ix.size.y > 0.0:
			total += ix.get_area()
	return total
