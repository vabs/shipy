class_name StarCounter
extends StatPill
## Pill showing the total stars earned: star icon + "n / total". set_count(n, total).


func _init() -> void:
	super._init(&"star", "0 / 54")


func set_count(n: int, total: int = -1) -> void:
	set_text("%d" % n if total < 0 else "%d / %d" % [n, total])
