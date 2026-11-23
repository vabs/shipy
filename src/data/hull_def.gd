class_name HullDef
extends Resource
## Ship hull (see docs/SPEC.md §4).

@export var id: StringName = &""
@export var display_name: String = ""
@export var width: int = 24
## Decks including the open-air top deck.
@export var decks: int = 4
@export var gangway_deck: int = 1
@export var power: int = 16
@export var water: int = 16
@export var max_staff: int = 4


func top_deck() -> int:
	return decks - 1
