class_name VoyagePauseFallback
extends Control
## Bare-bones pause overlay used until the shared PauseMenu exists.
## Signals: resume_pressed / restart_pressed / quit_pressed.

signal resume_pressed
signal restart_pressed
signal quit_pressed


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.08, 0.16, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var card := UIKit.card()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := UIKit.vbox(12)
	v.add_child(UIKit.title_label("Paused"))
	var b1 := UIKit.primary_button("Resume")
	b1.pressed.connect(func() -> void: resume_pressed.emit())
	var b2 := UIKit.secondary_button("Restart")
	b2.pressed.connect(func() -> void: restart_pressed.emit())
	var b3 := UIKit.ghost_button("Quit to map")
	b3.pressed.connect(func() -> void: quit_pressed.emit())
	v.add_child(b1)
	v.add_child(b2)
	v.add_child(b3)
	card.add_child(UIKit.with_margin(v, 18))
	add_child(card)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.is_action_pressed(&"cancel"):
		resume_pressed.emit()
		get_viewport().set_input_as_handled()
