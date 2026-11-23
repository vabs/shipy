class_name VoyageResultsFallback
extends Control
## Bare-bones results overlay used until the shared ResultsPanel exists.
## Same contract: show_result(result, unlocks, level), signals retry_pressed / next_pressed / map_pressed.

signal retry_pressed
signal next_pressed
signal map_pressed


func show_result(result: Dictionary, _unlocks: Dictionary, level: LevelDef) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.08, 0.16, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var card := UIKit.card()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := UIKit.vbox(10)
	var mut: bool = bool(result.get("mutiny", false))
	v.add_child(UIKit.title_label("Mutiny!" if mut else "Voyage complete"))
	var sr := UIKit.star_row(int(result.get("stars", 0)), 52.0)
	v.add_child(sr)
	v.add_child(UIKit.header_label("%s  -  rating %d%%  -  profit $%d" % [level.display_name, int(round(float(result.get("rating", 0.0)))), int(result.get("profit", 0))]))
	for g in result.get("goals", []):
		v.add_child(UIKit.small_label(("[x] " if g.get("met", false) else "[ ] ") + String(g.get("text", ""))))
	v.add_child(UIKit.small_label("Guests served %d, lost %d of %d" % [int(result.get("served", 0)), int(result.get("guests_lost", 0)), int(result.get("guests_total", 0))]))
	var row := UIKit.hbox(12)
	var b1 := UIKit.secondary_button("Retry")
	b1.pressed.connect(func() -> void: retry_pressed.emit())
	var b2 := UIKit.primary_button("Next")
	b2.pressed.connect(func() -> void: next_pressed.emit())
	var b3 := UIKit.ghost_button("Map")
	b3.pressed.connect(func() -> void: map_pressed.emit())
	row.add_child(b1)
	row.add_child(b2)
	row.add_child(b3)
	v.add_child(row)
	card.add_child(UIKit.with_margin(v, 14))
	add_child(card)
